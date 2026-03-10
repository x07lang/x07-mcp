#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import textwrap
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit


PIN_SCHEMA_URL = "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json"
PIN_SCHEMA_FILE = "registry/schema/server.schema.2025-12-11.json"
ALLOWED_META_KEY = "io.modelcontextprotocol.registry/publisher-provided"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PLACEHOLDER_SHA256 = "0" * 64
TRUST_BUNDLE_SCHEMA = "x07.mcp.trust.bundle@0.1.0"
TRUST_FRAMEWORK_SCHEMAS = {
    "x07.mcp.trust.framework@0.1.0",
    "x07.mcp.trust.framework@0.2.0",
    "x07.mcp.trust.framework@0.3.0",
}
TRUST_LOCK_SCHEMAS = {
    "x07.mcp.trust.lock@0.1.0",
    "x07.mcp.trust.lock@0.2.0",
}

ERR_PRM_UNSIGNED = "MCP_PUBLISH_PRM_UNSIGNED"
ERR_TRUST_POLICY_MISSING = "MCP_PUBLISH_TRUST_POLICY_MISSING"
ERR_TRUST_ISSUER_NOT_ALLOWED = "MCP_PUBLISH_TRUST_ISSUER_NOT_ALLOWED"
ERR_TRUST_PINS_MISSING = "MCP_PUBLISH_TRUST_PINS_MISSING"
ERR_PRM_SIGNATURE_INVALID = "MCP_PUBLISH_PRM_SIGNATURE_INVALID"
ERR_TRUST_META_MISMATCH = "MCP_PUBLISH_TRUST_META_MISMATCH"

_RS256_DIGEST_INFO_SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


@dataclass(frozen=True)
class PublishTrustConfig:
    require_signed_prm: bool
    trust_framework_path: str | None
    trust_lock_path: str | None
    emit_meta_summary: bool
    trust_pack_registry: str | None
    trust_pack_id: str | None
    trust_pack_version: str | None
    trust_pack_min_snapshot_version: int | None
    trust_pack_snapshot_sha256: str | None
    trust_pack_checkpoint_sha256: str | None
    trust_pack_root_path: str | None
    prm_path: str
    resource_metadata_path: str
    signer_iss_hint: str | None


@dataclass(frozen=True)
class LoadedTrustFramework:
    path: pathlib.Path
    repo_root: pathlib.Path
    framework: dict[str, Any]
    bundles: list[dict[str, Any]]
    bundle_paths: list[pathlib.Path]


def read_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_canonical_json(path: pathlib.Path, doc: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        handle.write(canonical_json_text(doc))


def canonical_json_text(doc: Any) -> str:
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def canonical_json_bytes(doc: Any) -> bytes:
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _package_transport_from_input(pkg: dict[str, Any]) -> dict[str, Any]:
    transport = pkg.get("transport")
    if isinstance(transport, dict):
        return transport
    registry_type = str(pkg.get("registryType", ""))
    if registry_type == "mcpb":
        return {"type": "stdio"}
    url = pkg.get("url")
    if isinstance(url, str) and url:
        return {"type": "streamable-http", "url": url}
    return {"type": "stdio"}


def _as_object(value: Any, *, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def _as_array(value: Any, *, field: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{field} must be an array")
    return value


def _as_nonempty_string(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty string")
    return value


def _is_https_url_no_fragment(url: str) -> bool:
    parsed = urlsplit(url)
    return parsed.scheme == "https" and bool(parsed.netloc) and not parsed.fragment


def _discover_repo_root(start: pathlib.Path) -> pathlib.Path:
    cur = start.resolve()
    if cur.is_file():
        cur = cur.parent
    for candidate in (cur, *cur.parents):
        if (candidate / ".git").exists():
            return candidate
    return cur


def _resolve_repo_relative_path(base_dir: pathlib.Path, rel_path: str, repo_root: pathlib.Path) -> pathlib.Path:
    rel = pathlib.Path(rel_path)
    if rel.is_absolute():
        raise ValueError(f"path must be relative: {rel_path}")
    resolved = (base_dir / rel).resolve()
    root = repo_root.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError(f"path escapes repo root: {rel_path}")
    return resolved


def _framework_sha256_hex(framework_doc: dict[str, Any]) -> str:
    canon = canonical_json_bytes(framework_doc)
    return hashlib.sha256(canon).hexdigest()


def _b64u_decode(text: str) -> bytes:
    if not isinstance(text, str) or not text:
        raise ValueError("invalid base64url value")
    pad = "=" * ((4 - (len(text) % 4)) % 4)
    try:
        return base64.urlsafe_b64decode(text + pad)
    except Exception as exc:  # pragma: no cover - defensive
        raise ValueError("invalid base64url encoding") from exc


def _b64u_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _parse_jwt_compact(token: str, *, context: str = "signed_metadata") -> tuple[dict[str, Any], dict[str, Any], bytes, bytes]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError(f"{context} must be a compact JWS")
    h_raw, p_raw, s_raw = parts
    try:
        header = json.loads(_b64u_decode(h_raw).decode("utf-8"))
        payload = json.loads(_b64u_decode(p_raw).decode("utf-8"))
    except Exception as exc:
        raise ValueError(f"{context} header/payload must be valid JSON") from exc
    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise ValueError(f"{context} header/payload must be JSON objects")
    signing_input = f"{h_raw}.{p_raw}".encode("ascii")
    signature = _b64u_decode(s_raw)
    return header, payload, signing_input, signature


def _jwt_int_claim(payload: dict[str, Any], key: str) -> int | None:
    value = payload.get(key)
    if isinstance(value, int):
        return value
    return None


def _verify_rs256(signing_input: bytes, signature: bytes, jwk: dict[str, Any]) -> bool:
    if str(jwk.get("kty", "")) != "RSA":
        return False
    n_txt = jwk.get("n")
    e_txt = jwk.get("e")
    if not isinstance(n_txt, str) or not isinstance(e_txt, str):
        return False
    try:
        n = int.from_bytes(_b64u_decode(n_txt), "big")
        e = int.from_bytes(_b64u_decode(e_txt), "big")
    except Exception:
        return False
    if n <= 0 or e <= 1:
        return False

    k = (n.bit_length() + 7) // 8
    if len(signature) != k:
        return False

    s = int.from_bytes(signature, "big")
    if s >= n:
        return False
    em = pow(s, e, n).to_bytes(k, "big")

    if len(em) < 11 or em[0:2] != b"\x00\x01":
        return False
    try:
        sep = em.index(b"\x00", 2)
    except ValueError:
        return False
    ps = em[2:sep]
    if len(ps) < 8 or any(byte != 0xFF for byte in ps):
        return False

    expected_tail = _RS256_DIGEST_INFO_SHA256_PREFIX + hashlib.sha256(signing_input).digest()
    return hmac.compare_digest(em[sep + 1 :], expected_tail)


def _der_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def _der_tlv(tag: int, payload: bytes) -> bytes:
    return bytes([tag]) + _der_len(len(payload)) + payload


def _der_oid(nums: list[int]) -> bytes:
    if len(nums) < 2:
        raise ValueError("invalid OID")
    out = bytes([40 * nums[0] + nums[1]])
    for num in nums[2:]:
        if num < 0:
            raise ValueError("invalid OID component")
        chunks: list[int] = []
        while True:
            chunks.append(num & 0x7F)
            num >>= 7
            if num == 0:
                break
        for idx, chunk in enumerate(reversed(chunks)):
            out += bytes([chunk | (0x80 if idx < len(chunks) - 1 else 0)])
    return _der_tlv(0x06, out)


def _der_seq(*vals: bytes) -> bytes:
    return _der_tlv(0x30, b"".join(vals))


def _der_bitstring(data: bytes) -> bytes:
    return _der_tlv(0x03, b"\x00" + data)


def _ed25519_public_pem_from_jwk_x(x_b64u: str) -> str:
    pub = _b64u_decode(x_b64u)
    if len(pub) != 32:
        raise ValueError("Ed25519 public key must be 32 bytes")
    alg = _der_seq(_der_oid([1, 3, 101, 112]))
    spki = _der_seq(alg, _der_bitstring(pub))
    b64 = base64.b64encode(spki).decode("ascii")
    wrapped = "\n".join(textwrap.wrap(b64, 64))
    return f"-----BEGIN PUBLIC KEY-----\n{wrapped}\n-----END PUBLIC KEY-----\n"


def _openssl_candidates() -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()

    def add(candidate: str | None) -> None:
        if not candidate:
            return
        if candidate in seen:
            return
        if not os.path.isfile(candidate):
            return
        if not os.access(candidate, os.X_OK):
            return
        seen.add(candidate)
        candidates.append(candidate)

    add(os.environ.get("X07_MCP_OPENSSL_BIN"))
    add(os.environ.get("OPENSSL_BIN"))
    add("/opt/homebrew/bin/openssl")
    add("/usr/local/bin/openssl")
    add("/opt/local/bin/openssl")
    add(shutil.which("openssl"))
    return candidates


def _verify_ed25519_openssl(signing_input: bytes, signature: bytes, jwk: dict[str, Any]) -> bool:
    openssl_bins = _openssl_candidates()
    if not openssl_bins:
        raise ValueError("openssl is required to verify EdDSA signed_metadata")
    if str(jwk.get("kty", "")) != "OKP":
        return False
    if str(jwk.get("crv", "")) != "Ed25519":
        return False
    x_txt = jwk.get("x")
    if not isinstance(x_txt, str) or not x_txt:
        return False

    pem = _ed25519_public_pem_from_jwk_x(x_txt)
    with tempfile.TemporaryDirectory(prefix="x07-mcp-trust-") as td:
        td_path = pathlib.Path(td)
        pem_path = td_path / "pub.pem"
        sig_path = td_path / "sig.bin"
        msg_path = td_path / "msg.bin"
        pem_path.write_text(pem, encoding="utf-8")
        sig_path.write_bytes(signature)
        msg_path.write_bytes(signing_input)

        for openssl_bin in openssl_bins:
            proc = subprocess.run(
                [
                    openssl_bin,
                    "pkeyutl",
                    "-verify",
                    "-pubin",
                    "-inkey",
                    str(pem_path),
                    "-sigfile",
                    str(sig_path),
                    "-rawin",
                    "-in",
                    str(msg_path),
                ],
                capture_output=True,
                text=True,
            )
            if proc.returncode == 0:
                return True
        return False


def _verify_signed_metadata_with_keys(
    token: str,
    *,
    keys: list[dict[str, Any]],
    allowed_algs: list[str],
    max_clock_skew_seconds: int,
    context: str = "signed_metadata",
) -> tuple[dict[str, Any], dict[str, Any]]:
    header, payload, signing_input, signature = _parse_jwt_compact(token, context=context)

    alg = header.get("alg")
    if not isinstance(alg, str) or not alg:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: {context} header missing alg")
    if alg == "none":
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: alg=none is not allowed")
    if allowed_algs and alg not in allowed_algs:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: alg {alg} is not allowed by trust policy")

    now_s = int(__import__("time").time())
    skew = max(0, max_clock_skew_seconds)
    exp = _jwt_int_claim(payload, "exp")
    nbf = _jwt_int_claim(payload, "nbf")
    if exp is not None and now_s > exp + skew:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: {context} is expired")
    if nbf is not None and now_s + skew < nbf:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: {context} is not yet valid")

    kid = header.get("kid")
    candidates = keys
    if isinstance(kid, str) and kid:
        candidates = [k for k in keys if str(k.get("kid", "")) == kid]

    if not candidates:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: no pinned key matches {context} kid")

    for jwk in candidates:
        key_alg = jwk.get("alg")
        if isinstance(key_alg, str) and key_alg and key_alg != alg:
            continue

        try:
            if alg == "RS256":
                if _verify_rs256(signing_input, signature, jwk):
                    return header, payload
            elif alg in {"EdDSA", "Ed25519"}:
                if _verify_ed25519_openssl(signing_input, signature, jwk):
                    return header, payload
        except ValueError:
            raise
        except Exception:
            continue

    raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signature verification failed")


def _validate_jwk_for_trust(jwk: dict[str, Any], *, field_prefix: str) -> None:
    kid = _as_nonempty_string(jwk.get("kid"), field=f"{field_prefix}.kid")
    kty = _as_nonempty_string(jwk.get("kty"), field=f"{field_prefix}.kty")
    if kty == "OKP":
        crv = _as_nonempty_string(jwk.get("crv"), field=f"{field_prefix}.crv")
        if crv != "Ed25519":
            raise ValueError(f"{field_prefix}.crv must be Ed25519")
        _as_nonempty_string(jwk.get("x"), field=f"{field_prefix}.x")
    elif kty == "RSA":
        _as_nonempty_string(jwk.get("n"), field=f"{field_prefix}.n")
        _as_nonempty_string(jwk.get("e"), field=f"{field_prefix}.e")
    else:
        raise ValueError(f"{field_prefix}.kty must be OKP or RSA")
    if kid.strip() != kid:
        raise ValueError(f"{field_prefix}.kid must not contain surrounding whitespace")


def _validate_trust_bundle(bundle: dict[str, Any], *, field_prefix: str = "bundle") -> None:
    schema_version = _as_nonempty_string(bundle.get("schema_version"), field=f"{field_prefix}.schema_version")
    if schema_version != TRUST_BUNDLE_SCHEMA:
        raise ValueError(f"{field_prefix}.schema_version must be {TRUST_BUNDLE_SCHEMA}")

    issuers = _as_array(bundle.get("issuers"), field=f"{field_prefix}.issuers")
    if not issuers:
        raise ValueError(f"{field_prefix}.issuers must not be empty")

    for idx, issuer_doc_any in enumerate(issuers):
        issuer_doc = _as_object(issuer_doc_any, field=f"{field_prefix}.issuers[{idx}]")
        issuer = _as_nonempty_string(issuer_doc.get("issuer"), field=f"{field_prefix}.issuers[{idx}].issuer")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.issuers[{idx}].issuer must be HTTPS URL without fragment")

        if "algs" in issuer_doc:
            algs = _as_array(issuer_doc.get("algs"), field=f"{field_prefix}.issuers[{idx}].algs")
            if not algs:
                raise ValueError(f"{field_prefix}.issuers[{idx}].algs must not be empty")
            for j, alg in enumerate(algs):
                _as_nonempty_string(alg, field=f"{field_prefix}.issuers[{idx}].algs[{j}]")

        for optional_seq_key in ("roles", "usage"):
            if optional_seq_key not in issuer_doc:
                continue
            vals = _as_array(
                issuer_doc.get(optional_seq_key),
                field=f"{field_prefix}.issuers[{idx}].{optional_seq_key}",
            )
            for seq_idx, value in enumerate(vals):
                _as_nonempty_string(
                    value,
                    field=f"{field_prefix}.issuers[{idx}].{optional_seq_key}[{seq_idx}]",
                )

        jwks_doc = _as_object(issuer_doc.get("jwks"), field=f"{field_prefix}.issuers[{idx}].jwks")
        keys = _as_array(jwks_doc.get("keys"), field=f"{field_prefix}.issuers[{idx}].jwks.keys")
        if not keys:
            raise ValueError(f"{field_prefix}.issuers[{idx}].jwks.keys must not be empty")
        for key_idx, key_any in enumerate(keys):
            jwk = _as_object(key_any, field=f"{field_prefix}.issuers[{idx}].jwks.keys[{key_idx}]")
            _validate_jwk_for_trust(jwk, field_prefix=f"{field_prefix}.issuers[{idx}].jwks.keys[{key_idx}]")


def _validate_verify_cfg_v1(verify: dict[str, Any], *, field_prefix: str) -> None:
    mode = verify.get("mode")
    if mode is not None and mode not in {"fail_closed", "best_effort"}:
        raise ValueError(f"{field_prefix}.mode invalid: {mode}")
    allowed_algs = verify.get("allowed_algs")
    if allowed_algs is not None:
        arr = _as_array(allowed_algs, field=f"{field_prefix}.allowed_algs")
        if not arr:
            raise ValueError(f"{field_prefix}.allowed_algs must not be empty")
        for alg_idx, alg in enumerate(arr):
            _as_nonempty_string(alg, field=f"{field_prefix}.allowed_algs[{alg_idx}]")
    max_clock_skew_seconds = verify.get("max_clock_skew_seconds")
    if max_clock_skew_seconds is not None:
        if not isinstance(max_clock_skew_seconds, int) or max_clock_skew_seconds < 0:
            raise ValueError(f"{field_prefix}.max_clock_skew_seconds must be >= 0")


def _validate_trust_framework_v1(framework: dict[str, Any], *, field_prefix: str = "framework") -> None:
    bundles = _as_array(framework.get("bundles"), field=f"{field_prefix}.bundles")
    if not bundles:
        raise ValueError(f"{field_prefix}.bundles must not be empty")
    for idx, bundle_ref_any in enumerate(bundles):
        bundle_ref = _as_object(bundle_ref_any, field=f"{field_prefix}.bundles[{idx}]")
        path_txt = _as_nonempty_string(bundle_ref.get("path"), field=f"{field_prefix}.bundles[{idx}].path")
        if pathlib.Path(path_txt).is_absolute():
            raise ValueError(f"{field_prefix}.bundles[{idx}].path must be relative")

    policies = framework.get("resource_policies")
    if policies is None:
        return

    policies_arr = _as_array(policies, field=f"{field_prefix}.resource_policies")
    for idx, policy_any in enumerate(policies_arr):
        policy = _as_object(policy_any, field=f"{field_prefix}.resource_policies[{idx}]")
        match = _as_object(policy.get("match"), field=f"{field_prefix}.resource_policies[{idx}].match")
        kind = _as_nonempty_string(match.get("kind"), field=f"{field_prefix}.resource_policies[{idx}].match.kind")
        if kind not in {"exact", "prefix", "hostSuffix"}:
            raise ValueError(f"{field_prefix}.resource_policies[{idx}].match.kind invalid: {kind}")
        _as_nonempty_string(match.get("value"), field=f"{field_prefix}.resource_policies[{idx}].match.value")

        allowed = _as_array(
            policy.get("allowed_prm_signers"),
            field=f"{field_prefix}.resource_policies[{idx}].allowed_prm_signers",
        )
        if not allowed:
            raise ValueError(f"{field_prefix}.resource_policies[{idx}].allowed_prm_signers must not be empty")
        for signer_idx, signer in enumerate(allowed):
            signer_txt = _as_nonempty_string(
                signer,
                field=f"{field_prefix}.resource_policies[{idx}].allowed_prm_signers[{signer_idx}]",
            )
            if not _is_https_url_no_fragment(signer_txt):
                raise ValueError(f"{field_prefix}.resource_policies[{idx}].allowed_prm_signers[{signer_idx}] must be HTTPS URL")

        verify_cfg = policy.get("verify_cfg")
        if verify_cfg is not None:
            verify = _as_object(verify_cfg, field=f"{field_prefix}.resource_policies[{idx}].verify_cfg")
            _validate_verify_cfg_v1(verify, field_prefix=f"{field_prefix}.resource_policies[{idx}].verify_cfg")


def _validate_as_policy_v2(as_policy: dict[str, Any], *, field_prefix: str) -> None:
    strategy = _as_nonempty_string(as_policy.get("strategy"), field=f"{field_prefix}.strategy")
    if strategy != "prefer_order_v1":
        raise ValueError(f"{field_prefix}.strategy must be prefer_order_v1")

    mode = _as_nonempty_string(as_policy.get("mode"), field=f"{field_prefix}.mode")
    if mode not in {"fail_closed", "fail_open"}:
        raise ValueError(f"{field_prefix}.mode must be fail_closed or fail_open")

    allowed = _as_array(as_policy.get("allowed_issuers"), field=f"{field_prefix}.allowed_issuers")
    for idx, issuer_any in enumerate(allowed):
        issuer = _as_nonempty_string(issuer_any, field=f"{field_prefix}.allowed_issuers[{idx}]")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.allowed_issuers[{idx}] must be HTTPS URL without fragment")

    prefer = _as_array(as_policy.get("prefer_issuers", []), field=f"{field_prefix}.prefer_issuers")
    for idx, issuer_any in enumerate(prefer):
        issuer = _as_nonempty_string(issuer_any, field=f"{field_prefix}.prefer_issuers[{idx}]")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.prefer_issuers[{idx}] must be HTTPS URL without fragment")

    require_https = as_policy.get("require_https")
    if require_https is not None and not isinstance(require_https, bool):
        raise ValueError(f"{field_prefix}.require_https must be boolean")


def _validate_prm_signed_policy_v2(policy: dict[str, Any], *, field_prefix: str) -> None:
    req = policy.get("require_signed_metadata")
    if req is not None and not isinstance(req, bool):
        raise ValueError(f"{field_prefix}.require_signed_metadata must be boolean")
    mode = policy.get("mode")
    if mode is not None:
        mode_txt = _as_nonempty_string(mode, field=f"{field_prefix}.mode")
        if mode_txt not in {"fail_closed", "best_effort", "fail_open"}:
            raise ValueError(f"{field_prefix}.mode invalid: {mode_txt}")

    allowed = _as_array(policy.get("allowed_signing_issuers", []), field=f"{field_prefix}.allowed_signing_issuers")
    for idx, issuer_any in enumerate(allowed):
        issuer = _as_nonempty_string(issuer_any, field=f"{field_prefix}.allowed_signing_issuers[{idx}]")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.allowed_signing_issuers[{idx}] must be HTTPS URL without fragment")


def _validate_source_ref_v1(source_any: Any, *, field_prefix: str) -> None:
    source = _as_object(source_any, field=field_prefix)
    kind = _as_nonempty_string(source.get("kind"), field=f"{field_prefix}.kind")
    if kind == "file":
        path_txt = _as_nonempty_string(source.get("path"), field=f"{field_prefix}.path")
        if pathlib.Path(path_txt).is_absolute():
            raise ValueError(f"{field_prefix}.path must be relative")
        return
    if kind == "url":
        url = _as_nonempty_string(source.get("url"), field=f"{field_prefix}.url")
        if not _is_https_url_no_fragment(url):
            raise ValueError(f"{field_prefix}.url must be HTTPS URL without fragment")
        return
    raise ValueError(f"{field_prefix}.kind must be file or url")


def _validate_trust_framework_v2(framework: dict[str, Any], *, field_prefix: str = "framework") -> None:
    mode = framework.get("mode")
    if mode is not None:
        _as_nonempty_string(mode, field=f"{field_prefix}.mode")

    bundle_publishers = _as_array(framework.get("bundle_publishers"), field=f"{field_prefix}.bundle_publishers")
    if not bundle_publishers:
        raise ValueError(f"{field_prefix}.bundle_publishers must not be empty")
    for idx, publisher_any in enumerate(bundle_publishers):
        publisher = _as_object(publisher_any, field=f"{field_prefix}.bundle_publishers[{idx}]")
        issuer = _as_nonempty_string(publisher.get("issuer"), field=f"{field_prefix}.bundle_publishers[{idx}].issuer")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.bundle_publishers[{idx}].issuer must be HTTPS URL without fragment")
        jwks_doc = _as_object(publisher.get("jwks"), field=f"{field_prefix}.bundle_publishers[{idx}].jwks")
        keys = _as_array(jwks_doc.get("keys"), field=f"{field_prefix}.bundle_publishers[{idx}].jwks.keys")
        if not keys:
            raise ValueError(f"{field_prefix}.bundle_publishers[{idx}].jwks.keys must not be empty")
        for key_idx, key_any in enumerate(keys):
            jwk = _as_object(key_any, field=f"{field_prefix}.bundle_publishers[{idx}].jwks.keys[{key_idx}]")
            _validate_jwk_for_trust(jwk, field_prefix=f"{field_prefix}.bundle_publishers[{idx}].jwks.keys[{key_idx}]")
        accepted_algs = _as_array(
            publisher.get("accepted_algs", []),
            field=f"{field_prefix}.bundle_publishers[{idx}].accepted_algs",
        )
        for alg_idx, alg in enumerate(accepted_algs):
            _as_nonempty_string(alg, field=f"{field_prefix}.bundle_publishers[{idx}].accepted_algs[{alg_idx}]")
        for int_field in ("max_ttl_secs", "clock_skew_secs"):
            value = publisher.get(int_field)
            if value is not None and (not isinstance(value, int) or value < 0):
                raise ValueError(f"{field_prefix}.bundle_publishers[{idx}].{int_field} must be >= 0")

    bundles = _as_array(framework.get("bundles"), field=f"{field_prefix}.bundles")
    if not bundles:
        raise ValueError(f"{field_prefix}.bundles must not be empty")
    for idx, bundle_ref_any in enumerate(bundles):
        bundle_ref = _as_object(bundle_ref_any, field=f"{field_prefix}.bundles[{idx}]")
        _as_nonempty_string(bundle_ref.get("id"), field=f"{field_prefix}.bundles[{idx}].id")
        source_any = bundle_ref.get("source")
        if source_any is not None:
            _validate_source_ref_v1(source_any, field_prefix=f"{field_prefix}.bundles[{idx}].source")
        else:
            path_txt = _as_nonempty_string(bundle_ref.get("path"), field=f"{field_prefix}.bundles[{idx}].path")
            if pathlib.Path(path_txt).is_absolute():
                raise ValueError(f"{field_prefix}.bundles[{idx}].path must be relative")
        require_signature = bool(bundle_ref.get("require_signature", False))
        if require_signature:
            sig_source_any = bundle_ref.get("sig_source")
            if sig_source_any is not None:
                _validate_source_ref_v1(sig_source_any, field_prefix=f"{field_prefix}.bundles[{idx}].sig_source")
            else:
                sig_jwt_path = _as_nonempty_string(
                    bundle_ref.get("sig_jwt_path"),
                    field=f"{field_prefix}.bundles[{idx}].sig_jwt_path",
                )
                if pathlib.Path(sig_jwt_path).is_absolute():
                    raise ValueError(f"{field_prefix}.bundles[{idx}].sig_jwt_path must be relative")
            publisher_issuer = _as_nonempty_string(
                bundle_ref.get("publisher_issuer"),
                field=f"{field_prefix}.bundles[{idx}].publisher_issuer",
            )
            if not _is_https_url_no_fragment(publisher_issuer):
                raise ValueError(f"{field_prefix}.bundles[{idx}].publisher_issuer must be HTTPS URL without fragment")

        for hash_field in ("expected_bundle_sha256", "expected_sig_jwt_sha256"):
            h = bundle_ref.get(hash_field)
            if h is None:
                continue
            h_txt = _as_nonempty_string(h, field=f"{field_prefix}.bundles[{idx}].{hash_field}")
            if not SHA256_RE.fullmatch(h_txt):
                raise ValueError(f"{field_prefix}.bundles[{idx}].{hash_field} must be 64 lowercase hex chars")

    resources = _as_array(framework.get("resources"), field=f"{field_prefix}.resources")
    if not resources:
        raise ValueError(f"{field_prefix}.resources must not be empty")
    for idx, resource_any in enumerate(resources):
        resource_doc = _as_object(resource_any, field=f"{field_prefix}.resources[{idx}]")
        resource = _as_nonempty_string(resource_doc.get("resource"), field=f"{field_prefix}.resources[{idx}].resource")
        if not _is_https_url_no_fragment(resource):
            raise ValueError(f"{field_prefix}.resources[{idx}].resource must be HTTPS URL without fragment")
        as_policy = _as_object(
            resource_doc.get("authorization_server_policy"),
            field=f"{field_prefix}.resources[{idx}].authorization_server_policy",
        )
        _validate_as_policy_v2(as_policy, field_prefix=f"{field_prefix}.resources[{idx}].authorization_server_policy")
        prm_policy = resource_doc.get("prm_signed_metadata_policy")
        if prm_policy is not None:
            _validate_prm_signed_policy_v2(
                _as_object(prm_policy, field=f"{field_prefix}.resources[{idx}].prm_signed_metadata_policy"),
                field_prefix=f"{field_prefix}.resources[{idx}].prm_signed_metadata_policy",
            )


def _validate_trust_framework(framework: dict[str, Any], *, field_prefix: str = "framework") -> None:
    schema_version = _as_nonempty_string(framework.get("schema_version"), field=f"{field_prefix}.schema_version")
    if schema_version not in TRUST_FRAMEWORK_SCHEMAS:
        wanted = ", ".join(sorted(TRUST_FRAMEWORK_SCHEMAS))
        raise ValueError(f"{field_prefix}.schema_version must be one of: {wanted}")
    _as_nonempty_string(framework.get("framework_id"), field=f"{field_prefix}.framework_id")

    if schema_version == "x07.mcp.trust.framework@0.1.0":
        _validate_trust_framework_v1(framework, field_prefix=field_prefix)
        return
    _validate_trust_framework_v2(framework, field_prefix=field_prefix)


def _load_trust_bundle(path: pathlib.Path) -> dict[str, Any]:
    doc = read_json(path)
    bundle = _as_object(doc, field=f"bundle file {path}")
    _validate_trust_bundle(bundle, field_prefix=f"bundle {path}")
    return bundle


def _load_trust_framework(path: pathlib.Path) -> dict[str, Any]:
    doc = read_json(path)
    framework = _as_object(doc, field=f"framework file {path}")
    _validate_trust_framework(framework, field_prefix=f"framework {path}")
    return framework


def load_trust_framework_with_bundles(
    framework_path: pathlib.Path,
    *,
    repo_root: pathlib.Path | None = None,
) -> LoadedTrustFramework:
    framework_path = framework_path.resolve()
    repo = repo_root.resolve() if repo_root is not None else _discover_repo_root(framework_path)
    framework = _load_trust_framework(framework_path)

    bundles: list[dict[str, Any]] = []
    bundle_paths: list[pathlib.Path] = []
    for idx, bundle_ref_any in enumerate(_as_array(framework.get("bundles"), field="framework.bundles")):
        bundle_ref = _as_object(bundle_ref_any, field=f"framework.bundles[{idx}]")
        bundle_path: pathlib.Path | None = None
        path_any = bundle_ref.get("path")
        if isinstance(path_any, str) and path_any:
            bundle_path = _resolve_repo_relative_path(framework_path.parent, path_any, repo)
        else:
            source_any = bundle_ref.get("source")
            if isinstance(source_any, dict) and str(source_any.get("kind", "")) == "file":
                source_rel = _as_nonempty_string(source_any.get("path"), field=f"framework.bundles[{idx}].source.path")
                bundle_path = _resolve_repo_relative_path(framework_path.parent, source_rel, repo)

        if bundle_path is not None:
            if not bundle_path.is_file():
                raise ValueError(f"trust bundle file not found: {bundle_path}")
            bundles.append(_load_trust_bundle(bundle_path))
            bundle_paths.append(bundle_path)
        else:
            bundles.append({})
            bundle_paths.append(framework_path)
    return LoadedTrustFramework(
        path=framework_path,
        repo_root=repo,
        framework=framework,
        bundles=bundles,
        bundle_paths=bundle_paths,
    )


def _host_suffix_match(host: str, suffix: str) -> bool:
    clean = suffix.lstrip(".")
    if not clean:
        return False
    return host == clean or host.endswith(f".{clean}")


def _policy_matches_resource(policy: dict[str, Any], resource_url: str) -> tuple[bool, str, int]:
    match = _as_object(policy.get("match"), field="policy.match")
    kind = _as_nonempty_string(match.get("kind"), field="policy.match.kind")
    value = _as_nonempty_string(match.get("value"), field="policy.match.value")

    if kind == "exact":
        return resource_url == value, kind, len(value)
    if kind == "prefix":
        return resource_url.startswith(value), kind, len(value)
    if kind == "hostSuffix":
        parsed = urlsplit(resource_url)
        host = parsed.hostname or ""
        return _host_suffix_match(host, value), kind, len(value)
    return False, kind, len(value)


def _stable_unique(items: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def resolve_trust_policy(framework_doc: dict[str, Any], resource_url: str) -> dict[str, Any]:
    policies = _as_array(framework_doc.get("resource_policies", []), field="framework.resource_policies")
    defaults = framework_doc.get("defaults")
    defaults_obj = _as_object(defaults, field="framework.defaults") if defaults is not None else {}

    buckets: dict[str, list[tuple[int, int, dict[str, Any]]]] = {"exact": [], "prefix": [], "hostSuffix": []}
    for idx, policy_any in enumerate(policies):
        policy = _as_object(policy_any, field=f"framework.resource_policies[{idx}]")
        matched, kind, specificity = _policy_matches_resource(policy, resource_url)
        if matched and kind in buckets:
            buckets[kind].append((specificity, idx, policy))

    chosen_kind = ""
    for kind in ("exact", "prefix", "hostSuffix"):
        if buckets[kind]:
            chosen_kind = kind
            break

    selected: list[dict[str, Any]] = []
    if chosen_kind:
        ordered = sorted(buckets[chosen_kind], key=lambda row: (-row[0], row[1]))
        selected = [row[2] for row in ordered]

    allowed_signers: list[str] = []
    require_signed = bool(defaults_obj.get("require_signed_prm", False))
    verify_cfg: dict[str, Any] = {}
    if isinstance(defaults_obj.get("verify_cfg"), dict):
        verify_cfg = dict(defaults_obj["verify_cfg"])

    for policy in selected:
        allowed = _as_array(policy.get("allowed_prm_signers", []), field="policy.allowed_prm_signers")
        for signer in allowed:
            signer_txt = _as_nonempty_string(signer, field="policy.allowed_prm_signers[]")
            allowed_signers.append(signer_txt)
        if "require_signed_prm" in policy:
            require_signed = bool(policy.get("require_signed_prm"))
        if isinstance(policy.get("verify_cfg"), dict):
            verify_cfg = dict(policy["verify_cfg"])

    return {
        "matched": bool(selected),
        "match_kind": chosen_kind,
        "allowed_prm_signers": _stable_unique(allowed_signers),
        "require_signed_prm": require_signed,
        "verify_cfg": verify_cfg,
    }


def _framework_schema_version(framework_doc: dict[str, Any]) -> str:
    return str(framework_doc.get("schema_version", ""))


def _resolve_resource_entry_v2(framework_doc: dict[str, Any], resource_url: str) -> dict[str, Any] | None:
    resources = _as_array(framework_doc.get("resources", []), field="framework.resources")
    for resource_any in resources:
        resource_doc = _as_object(resource_any, field="framework.resources[]")
        if str(resource_doc.get("resource", "")) == resource_url:
            return resource_doc
    return None


def resolve_prm_signed_policy(framework_doc: dict[str, Any], resource_url: str) -> dict[str, Any]:
    schema_version = _framework_schema_version(framework_doc)
    if schema_version in {"x07.mcp.trust.framework@0.2.0", "x07.mcp.trust.framework@0.3.0"}:
        resource_entry = _resolve_resource_entry_v2(framework_doc, resource_url)
        if resource_entry is None:
            return {
                "matched": False,
                "allowed_prm_signers": [],
                "require_signed_prm": True,
                "verify_cfg": {},
            }
        signed_policy = _as_object(
            resource_entry.get("prm_signed_metadata_policy", {}),
            field="framework.resources[].prm_signed_metadata_policy",
        )
        allowed = _as_array(signed_policy.get("allowed_signing_issuers", []), field="signed_policy.allowed_signing_issuers")
        allowed_issuers: list[str] = []
        for idx, issuer_any in enumerate(allowed):
            issuer = _as_nonempty_string(issuer_any, field=f"signed_policy.allowed_signing_issuers[{idx}]")
            allowed_issuers.append(issuer)
        require_signed = bool(signed_policy.get("require_signed_metadata", True))
        return {
            "matched": True,
            "allowed_prm_signers": _stable_unique(allowed_issuers),
            "require_signed_prm": require_signed,
            "verify_cfg": {},
        }
    return resolve_trust_policy(framework_doc, resource_url)


def resolve_as_policy(framework_doc: dict[str, Any], resource_url: str) -> dict[str, Any] | None:
    if _framework_schema_version(framework_doc) not in {
        "x07.mcp.trust.framework@0.2.0",
        "x07.mcp.trust.framework@0.3.0",
    }:
        return None
    resource_entry = _resolve_resource_entry_v2(framework_doc, resource_url)
    if resource_entry is None:
        return None
    return _as_object(
        resource_entry.get("authorization_server_policy"),
        field="framework.resources[].authorization_server_policy",
    )


def _is_https_url_no_query_no_fragment(url: str) -> bool:
    parsed = urlsplit(url)
    return parsed.scheme == "https" and bool(parsed.netloc) and not parsed.query and not parsed.fragment


def select_authorization_server_v1(policy: dict[str, Any], prm_authorization_servers: list[str]) -> dict[str, Any]:
    mode = _as_nonempty_string(policy.get("mode", "fail_closed"), field="as_policy.mode")
    if mode not in {"fail_closed", "fail_open"}:
        raise ValueError(f"as_policy.mode invalid: {mode}")
    require_https = bool(policy.get("require_https", True))

    allowed_raw = _as_array(policy.get("allowed_issuers", []), field="as_policy.allowed_issuers")
    allowed_issuers: list[str] = []
    for idx, issuer_any in enumerate(allowed_raw):
        issuer = _as_nonempty_string(issuer_any, field=f"as_policy.allowed_issuers[{idx}]")
        allowed_issuers.append(issuer)
    allowed_set = set(allowed_issuers)
    if not allowed_issuers and mode == "fail_closed":
        raise ValueError("as_no_allowed_issuer: as_policy.allowed_issuers is empty in fail_closed mode")

    prefer_raw = _as_array(policy.get("prefer_issuers", []), field="as_policy.prefer_issuers")
    prefer_issuers: list[str] = []
    for idx, issuer_any in enumerate(prefer_raw):
        issuer = _as_nonempty_string(issuer_any, field=f"as_policy.prefer_issuers[{idx}]")
        prefer_issuers.append(issuer)

    valid: list[str] = []
    rejected: list[dict[str, str]] = []
    for idx, issuer_any in enumerate(prm_authorization_servers):
        if not isinstance(issuer_any, str) or not issuer_any:
            rejected.append({"issuer": str(issuer_any), "reason_code": "issuer_format_invalid"})
            continue
        issuer = issuer_any
        parsed = urlsplit(issuer)
        if require_https:
            ok = _is_https_url_no_query_no_fragment(issuer)
        else:
            ok = parsed.scheme in {"http", "https"} and bool(parsed.netloc) and not parsed.query and not parsed.fragment
        if not ok:
            rejected.append({"issuer": issuer, "reason_code": "issuer_format_invalid"})
            continue
        valid.append(issuer)

    filtered: list[str] = []
    for issuer in valid:
        if not allowed_issuers or issuer in allowed_set:
            filtered.append(issuer)
        else:
            rejected.append({"issuer": issuer, "reason_code": "not_allowed"})

    selected_issuer = ""
    if filtered:
        if prefer_issuers:
            filtered_set = set(filtered)
            for preferred in prefer_issuers:
                if preferred in filtered_set:
                    selected_issuer = preferred
                    break
        if not selected_issuer:
            selected_issuer = sorted(filtered)[0]
    else:
        if mode == "fail_closed":
            raise ValueError("as_no_allowed_issuer")
        if valid:
            selected_issuer = valid[0]

    if not selected_issuer:
        raise ValueError("as_no_allowed_issuer")

    for issuer in filtered:
        if issuer == selected_issuer:
            continue
        reason = "not_preferred" if issuer in set(prefer_issuers) or prefer_issuers else "not_selected"
        rejected.append({"issuer": issuer, "reason_code": reason})

    return {
        "selected_issuer": selected_issuer,
        "rejected": rejected,
    }


def trust_keys_for_issuer(loaded: LoadedTrustFramework, issuer: str) -> tuple[list[dict[str, Any]], list[str]]:
    keys: list[dict[str, Any]] = []
    allowed_algs: list[str] = []

    for bundle in loaded.bundles:
        issuers_any = bundle.get("issuers")
        if not isinstance(issuers_any, list):
            continue
        issuers = _as_array(issuers_any, field="bundle.issuers")
        for issuer_any in issuers:
            issuer_doc = _as_object(issuer_any, field="bundle.issuers[]")
            if str(issuer_doc.get("issuer", "")) != issuer:
                continue

            algs = _as_array(issuer_doc.get("algs", []), field="bundle.issuers[].algs")
            for alg in algs:
                allowed_algs.append(_as_nonempty_string(alg, field="bundle.issuers[].algs[]"))

            jwks_doc = _as_object(issuer_doc.get("jwks"), field="bundle.issuers[].jwks")
            jwks_keys = _as_array(jwks_doc.get("keys", []), field="bundle.issuers[].jwks.keys")
            for key_any in jwks_keys:
                jwk = _as_object(key_any, field="bundle.issuers[].jwks.keys[]")
                _validate_jwk_for_trust(jwk, field_prefix="bundle.issuers[].jwks.keys[]")
                keys.append(jwk)

    if not keys:
        publisher = _bundle_publishers_index(loaded.framework).get(issuer)
        if publisher is not None:
            jwks_doc = _as_object(publisher.get("jwks"), field="framework.bundle_publishers[].jwks")
            jwks_keys = _as_array(jwks_doc.get("keys"), field="framework.bundle_publishers[].jwks.keys")
            for key_any in jwks_keys:
                jwk = _as_object(key_any, field="framework.bundle_publishers[].jwks.keys[]")
                _validate_jwk_for_trust(jwk, field_prefix="framework.bundle_publishers[].jwks.keys[]")
                keys.append(jwk)
            accepted_algs_any = _as_array(
                publisher.get("accepted_algs", []),
                field="framework.bundle_publishers[].accepted_algs",
            )
            for alg in accepted_algs_any:
                if isinstance(alg, str) and alg:
                    allowed_algs.append(alg)

    deduped_keys: list[dict[str, Any]] = []
    seen: set[str] = set()
    for jwk in keys:
        marker = canonical_json_text(jwk)
        if marker in seen:
            continue
        seen.add(marker)
        deduped_keys.append(jwk)

    return deduped_keys, _stable_unique(allowed_algs)


def _canonical_sha256_hex(doc: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json_bytes(doc)).hexdigest()


def _read_text(path: pathlib.Path) -> str:
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def _validate_trust_lock(lock_doc: dict[str, Any], *, field_prefix: str = "trust_lock") -> None:
    schema_version = _as_nonempty_string(lock_doc.get("schema_version"), field=f"{field_prefix}.schema_version")
    if schema_version not in TRUST_LOCK_SCHEMAS:
        wanted = ", ".join(sorted(TRUST_LOCK_SCHEMAS))
        raise ValueError(f"{field_prefix}.schema_version must be one of: {wanted}")
    _as_nonempty_string(lock_doc.get("framework_id"), field=f"{field_prefix}.framework_id")
    _as_nonempty_string(lock_doc.get("generated_at"), field=f"{field_prefix}.generated_at")

    bundles = _as_array(lock_doc.get("bundles"), field=f"{field_prefix}.bundles")
    if not bundles:
        raise ValueError(f"{field_prefix}.bundles must not be empty")
    for idx, bundle_any in enumerate(bundles):
        bundle = _as_object(bundle_any, field=f"{field_prefix}.bundles[{idx}]")
        _as_nonempty_string(bundle.get("id"), field=f"{field_prefix}.bundles[{idx}].id")
        if schema_version == "x07.mcp.trust.lock@0.1.0":
            for rel_key in ("path", "sig_jwt_path"):
                rel = _as_nonempty_string(bundle.get(rel_key), field=f"{field_prefix}.bundles[{idx}].{rel_key}")
                if pathlib.Path(rel).is_absolute():
                    raise ValueError(f"{field_prefix}.bundles[{idx}].{rel_key} must be relative")
            for hash_key in ("bundle_sha256", "sig_jwt_sha256"):
                h = _as_nonempty_string(bundle.get(hash_key), field=f"{field_prefix}.bundles[{idx}].{hash_key}")
                if not SHA256_RE.fullmatch(h):
                    raise ValueError(f"{field_prefix}.bundles[{idx}].{hash_key} must be 64 lowercase hex chars")
        else:
            bundle_url = _as_nonempty_string(bundle.get("bundle_url"), field=f"{field_prefix}.bundles[{idx}].bundle_url")
            sig_url = _as_nonempty_string(bundle.get("sig_url"), field=f"{field_prefix}.bundles[{idx}].sig_url")
            if not _is_https_url_no_fragment(bundle_url):
                raise ValueError(f"{field_prefix}.bundles[{idx}].bundle_url must be HTTPS URL without fragment")
            if not _is_https_url_no_fragment(sig_url):
                raise ValueError(f"{field_prefix}.bundles[{idx}].sig_url must be HTTPS URL without fragment")
            for hash_key in ("bundle_sha256", "sig_sha256"):
                h = _as_nonempty_string(bundle.get(hash_key), field=f"{field_prefix}.bundles[{idx}].{hash_key}")
                if not SHA256_RE.fullmatch(h):
                    raise ValueError(f"{field_prefix}.bundles[{idx}].{hash_key} must be 64 lowercase hex chars")
        issuer = _as_nonempty_string(bundle.get("publisher_issuer"), field=f"{field_prefix}.bundles[{idx}].publisher_issuer")
        if not _is_https_url_no_fragment(issuer):
            raise ValueError(f"{field_prefix}.bundles[{idx}].publisher_issuer must be HTTPS URL without fragment")
        _as_nonempty_string(bundle.get("kid"), field=f"{field_prefix}.bundles[{idx}].kid")
        _as_nonempty_string(bundle.get("alg"), field=f"{field_prefix}.bundles[{idx}].alg")


def _load_trust_lock(path: pathlib.Path) -> dict[str, Any]:
    doc = read_json(path)
    lock_doc = _as_object(doc, field=f"trust lock file {path}")
    _validate_trust_lock(lock_doc, field_prefix=f"trust lock {path}")
    return lock_doc


def _validate_registry_root_doc(root_doc: dict[str, Any], *, field_prefix: str = "trust_pack.root") -> None:
    _as_nonempty_string(root_doc.get("registry_id"), field=f"{field_prefix}.registry_id")
    _as_nonempty_string(root_doc.get("expires"), field=f"{field_prefix}.expires")
    _as_object(root_doc.get("keys"), field=f"{field_prefix}.keys")
    roles = _as_object(root_doc.get("roles"), field=f"{field_prefix}.roles")
    for role_name in ("timestamp", "snapshot", "witness"):
        if role_name not in roles:
            raise ValueError(f"{field_prefix}.roles.{role_name} is required")
        role_obj = _as_object(roles.get(role_name), field=f"{field_prefix}.roles.{role_name}")
        keyids = _as_array(role_obj.get("keyids"), field=f"{field_prefix}.roles.{role_name}.keyids")
        if not keyids:
            raise ValueError(f"{field_prefix}.roles.{role_name}.keyids must not be empty")
        for idx, kid in enumerate(keyids):
            _as_nonempty_string(kid, field=f"{field_prefix}.roles.{role_name}.keyids[{idx}]")
        threshold = role_obj.get("threshold")
        if not isinstance(threshold, int) or threshold <= 0:
            raise ValueError(f"{field_prefix}.roles.{role_name}.threshold must be integer > 0")


def _framework_requires_signed_bundles(framework_doc: dict[str, Any]) -> bool:
    if _framework_schema_version(framework_doc) not in {
        "x07.mcp.trust.framework@0.2.0",
        "x07.mcp.trust.framework@0.3.0",
    }:
        return False
    bundles = _as_array(framework_doc.get("bundles", []), field="framework.bundles")
    for bundle_any in bundles:
        bundle_ref = _as_object(bundle_any, field="framework.bundles[]")
        if bool(bundle_ref.get("require_signature", False)):
            return True
    return False


def _framework_has_remote_sources(framework_doc: dict[str, Any]) -> bool:
    if _framework_schema_version(framework_doc) != "x07.mcp.trust.framework@0.3.0":
        return False
    bundles = _as_array(framework_doc.get("bundles", []), field="framework.bundles")
    for bundle_any in bundles:
        bundle_ref = _as_object(bundle_any, field="framework.bundles[]")
        source = bundle_ref.get("source")
        if isinstance(source, dict) and str(source.get("kind", "")) == "url":
            return True
        sig_source = bundle_ref.get("sig_source")
        if isinstance(sig_source, dict) and str(sig_source.get("kind", "")) == "url":
            return True
    return False


def _default_as_selection_strategy(framework_doc: dict[str, Any]) -> str:
    if _framework_schema_version(framework_doc) not in {
        "x07.mcp.trust.framework@0.2.0",
        "x07.mcp.trust.framework@0.3.0",
    }:
        return ""
    resources = _as_array(framework_doc.get("resources", []), field="framework.resources")
    for resource_any in resources:
        resource_doc = _as_object(resource_any, field="framework.resources[]")
        as_policy = _as_object(
            resource_doc.get("authorization_server_policy"),
            field="framework.resources[].authorization_server_policy",
        )
        strategy = as_policy.get("strategy")
        if isinstance(strategy, str) and strategy:
            return strategy
    return ""


def _bundle_publishers_index(framework_doc: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    if _framework_schema_version(framework_doc) not in {
        "x07.mcp.trust.framework@0.2.0",
        "x07.mcp.trust.framework@0.3.0",
    }:
        return out
    publishers = _as_array(framework_doc.get("bundle_publishers", []), field="framework.bundle_publishers")
    for idx, publisher_any in enumerate(publishers):
        publisher = _as_object(publisher_any, field=f"framework.bundle_publishers[{idx}]")
        issuer = _as_nonempty_string(publisher.get("issuer"), field=f"framework.bundle_publishers[{idx}].issuer")
        out[issuer] = publisher
    return out


def _lock_entries_by_id(lock_doc: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    bundles = _as_array(lock_doc.get("bundles", []), field="trust_lock.bundles")
    for idx, bundle_any in enumerate(bundles):
        bundle = _as_object(bundle_any, field=f"trust_lock.bundles[{idx}]")
        bundle_id = _as_nonempty_string(bundle.get("id"), field=f"trust_lock.bundles[{idx}].id")
        out[bundle_id] = bundle
    return out


def _aud_contains(payload: dict[str, Any], want: str) -> bool:
    aud = payload.get("aud")
    if isinstance(aud, str):
        return aud == want
    if isinstance(aud, list):
        return want in [a for a in aud if isinstance(a, str)]
    return False


def _verify_framework_bundles_with_lock(
    loaded: LoadedTrustFramework,
    *,
    trust_lock_path: pathlib.Path | None,
) -> tuple[str, dict[str, Any] | None]:
    schema_version = _framework_schema_version(loaded.framework)
    if schema_version not in {"x07.mcp.trust.framework@0.2.0", "x07.mcp.trust.framework@0.3.0"}:
        return PLACEHOLDER_SHA256, None

    requires_lock = _framework_requires_signed_bundles(loaded.framework) or _framework_has_remote_sources(loaded.framework)
    lock_doc: dict[str, Any] | None = None
    lock_sha = PLACEHOLDER_SHA256
    if trust_lock_path is not None:
        if not trust_lock_path.is_file():
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock file not found: {trust_lock_path}")
        lock_doc = _load_trust_lock(trust_lock_path)
        lock_sha = _canonical_sha256_hex(lock_doc)
        framework_id = _as_nonempty_string(loaded.framework.get("framework_id"), field="framework.framework_id")
        if str(lock_doc.get("framework_id", "")) != framework_id:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock framework_id mismatch (want {framework_id})")
    elif requires_lock:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock path is required for signed trust bundles")

    if not requires_lock:
        return lock_sha, lock_doc

    if schema_version == "x07.mcp.trust.framework@0.3.0":
        if lock_doc is None:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock path is required for remote trust sources")
        lock_index = _lock_entries_by_id(lock_doc)
        bundles = _as_array(loaded.framework.get("bundles", []), field="framework.bundles")
        for idx, bundle_ref_any in enumerate(bundles):
            bundle_ref = _as_object(bundle_ref_any, field=f"framework.bundles[{idx}]")
            bundle_id = _as_nonempty_string(bundle_ref.get("id"), field=f"framework.bundles[{idx}].id")
            require_signature = bool(bundle_ref.get("require_signature", False))
            source = bundle_ref.get("source")
            sig_source = bundle_ref.get("sig_source")

            source_kind = str(source.get("kind", "")) if isinstance(source, dict) else ""
            sig_source_kind = str(sig_source.get("kind", "")) if isinstance(sig_source, dict) else ""
            source_url = str(source.get("url", "")) if source_kind == "url" and isinstance(source, dict) else ""
            sig_source_url = str(sig_source.get("url", "")) if sig_source_kind == "url" and isinstance(sig_source, dict) else ""

            needs_lock_entry = require_signature or source_kind == "url" or sig_source_kind == "url"
            if not needs_lock_entry:
                continue
            lock_entry = lock_index.get(bundle_id)
            if lock_entry is None:
                raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock missing bundle entry for id={bundle_id}")

            if source_kind == "url":
                if str(lock_entry.get("bundle_url", "")) != source_url:
                    raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock bundle_url mismatch for bundle {bundle_id}")
            if sig_source_kind == "url":
                if str(lock_entry.get("sig_url", "")) != sig_source_url:
                    raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock sig_url mismatch for bundle {bundle_id}")

            if require_signature:
                publisher_issuer = _as_nonempty_string(
                    bundle_ref.get("publisher_issuer"),
                    field=f"framework.bundles[{idx}].publisher_issuer",
                )
                lock_publisher_issuer = _as_nonempty_string(
                    lock_entry.get("publisher_issuer"),
                    field=f"trust_lock.bundles[{idx}].publisher_issuer",
                )
                if lock_publisher_issuer != publisher_issuer:
                    raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock publisher_issuer mismatch for bundle {bundle_id}")
                _as_nonempty_string(lock_entry.get("kid"), field=f"trust_lock.bundles[{idx}].kid")
                _as_nonempty_string(lock_entry.get("alg"), field=f"trust_lock.bundles[{idx}].alg")

        return lock_sha, lock_doc

    publisher_index = _bundle_publishers_index(loaded.framework)
    lock_index = _lock_entries_by_id(lock_doc) if lock_doc is not None else {}
    bundles = _as_array(loaded.framework.get("bundles", []), field="framework.bundles")

    for idx, bundle_ref_any in enumerate(bundles):
        bundle_ref = _as_object(bundle_ref_any, field=f"framework.bundles[{idx}]")
        if not bool(bundle_ref.get("require_signature", False)):
            continue

        bundle_id = _as_nonempty_string(bundle_ref.get("id"), field=f"framework.bundles[{idx}].id")
        bundle_doc = loaded.bundles[idx]
        bundle_path = loaded.bundle_paths[idx]
        bundle_rel = _as_nonempty_string(bundle_ref.get("path"), field=f"framework.bundles[{idx}].path")

        bundle_sha = _canonical_sha256_hex(bundle_doc)
        expected_bundle_sha = bundle_ref.get("expected_bundle_sha256")
        if expected_bundle_sha is not None and str(expected_bundle_sha) != bundle_sha:
            raise ValueError(
                f"{ERR_TRUST_PINS_MISSING}: bundle sha mismatch for {bundle_id} "
                f"(got={bundle_sha} want={expected_bundle_sha})"
            )

        sig_rel = _as_nonempty_string(bundle_ref.get("sig_jwt_path"), field=f"framework.bundles[{idx}].sig_jwt_path")
        sig_path = _resolve_repo_relative_path(loaded.path.parent, sig_rel, loaded.repo_root)
        if not sig_path.is_file():
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust bundle signature file not found: {sig_path}")
        sig_text = _read_text(sig_path).strip()
        if not sig_text:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust bundle signature is empty: {sig_path}")
        sig_sha = sha256_file(sig_path)
        expected_sig_sha = bundle_ref.get("expected_sig_jwt_sha256")
        if expected_sig_sha is not None and str(expected_sig_sha) != sig_sha:
            raise ValueError(
                f"{ERR_TRUST_PINS_MISSING}: bundle signature sha mismatch for {bundle_id} "
                f"(got={sig_sha} want={expected_sig_sha})"
            )

        lock_entry = lock_index.get(bundle_id)
        if lock_entry is None:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock missing bundle entry for id={bundle_id}")
        if str(lock_entry.get("path", "")) != bundle_rel:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock path mismatch for bundle {bundle_id}")
        if str(lock_entry.get("sig_jwt_path", "")) != sig_rel:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock sig_jwt_path mismatch for bundle {bundle_id}")
        if str(lock_entry.get("bundle_sha256", "")) != bundle_sha:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock bundle_sha256 mismatch for bundle {bundle_id}")
        if str(lock_entry.get("sig_jwt_sha256", "")) != sig_sha:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock sig_jwt_sha256 mismatch for bundle {bundle_id}")

        publisher_issuer = _as_nonempty_string(
            bundle_ref.get("publisher_issuer"),
            field=f"framework.bundles[{idx}].publisher_issuer",
        )
        lock_publisher_issuer = _as_nonempty_string(
            lock_entry.get("publisher_issuer"),
            field=f"trust_lock.bundles[{idx}].publisher_issuer",
        )
        if lock_publisher_issuer != publisher_issuer:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock publisher_issuer mismatch for bundle {bundle_id}")

        publisher = publisher_index.get(publisher_issuer)
        if publisher is None:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: bundle publisher not found in framework: {publisher_issuer}")
        jwks_doc = _as_object(publisher.get("jwks"), field="framework.bundle_publishers[].jwks")
        keys_any = _as_array(jwks_doc.get("keys"), field="framework.bundle_publishers[].jwks.keys")
        keys: list[dict[str, Any]] = []
        for key_idx, key_any in enumerate(keys_any):
            jwk = _as_object(key_any, field=f"framework.bundle_publishers[].jwks.keys[{key_idx}]")
            _validate_jwk_for_trust(jwk, field_prefix=f"framework.bundle_publishers[].jwks.keys[{key_idx}]")
            keys.append(jwk)

        accepted_algs_any = _as_array(publisher.get("accepted_algs", []), field="framework.bundle_publishers[].accepted_algs")
        accepted_algs = [str(a) for a in accepted_algs_any if isinstance(a, str) and a]
        if not accepted_algs:
            accepted_algs = ["Ed25519", "EdDSA", "RS256"]
        clock_skew = int(publisher.get("clock_skew_secs", 60))
        max_ttl_secs = int(publisher.get("max_ttl_secs", 7776000))

        header, payload = _verify_signed_metadata_with_keys(
            sig_text,
            keys=keys,
            allowed_algs=accepted_algs,
            max_clock_skew_seconds=max(0, clock_skew),
            context="trust_bundle_sig",
        )

        if str(payload.get("iss", "")) != publisher_issuer:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig issuer mismatch for bundle {bundle_id}")
        if str(payload.get("sub", "")) != bundle_id:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig sub mismatch for bundle {bundle_id}")
        if not _aud_contains(payload, "x07-mcp-trust-bundle"):
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig aud missing x07-mcp-trust-bundle")
        if str(payload.get("bundle_sha256", "")) != bundle_sha:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig bundle_sha256 mismatch for bundle {bundle_id}")
        bundle_version = str(bundle_doc.get("bundle_version") or bundle_doc.get("version") or "")
        if bundle_version and str(payload.get("bundle_version", "")) != bundle_version:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig bundle_version mismatch for bundle {bundle_id}")

        iat = _jwt_int_claim(payload, "iat")
        exp = _jwt_int_claim(payload, "exp")
        if iat is None or exp is None:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig requires iat/exp claims")
        if exp < iat:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig exp < iat")
        if max_ttl_secs >= 0 and exp - iat > max_ttl_secs:
            raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: trust_bundle_sig ttl exceeds publisher max_ttl_secs")

        lock_kid = _as_nonempty_string(lock_entry.get("kid"), field="trust_lock.bundles[].kid")
        lock_alg = _as_nonempty_string(lock_entry.get("alg"), field="trust_lock.bundles[].alg")
        header_kid = _as_nonempty_string(header.get("kid"), field="trust_bundle_sig.header.kid")
        header_alg = _as_nonempty_string(header.get("alg"), field="trust_bundle_sig.header.alg")
        if header_kid != lock_kid:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock kid mismatch for bundle {bundle_id}")
        if header_alg != lock_alg:
            raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust lock alg mismatch for bundle {bundle_id}")

    return lock_sha, lock_doc


def _get_nested_object(doc: dict[str, Any], path: list[str]) -> dict[str, Any] | None:
    cur: Any = doc
    for key in path:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    if isinstance(cur, dict):
        return cur
    return None


def _get_nested_string(doc: dict[str, Any], path: list[str]) -> str | None:
    cur: Any = doc
    for key in path:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    if isinstance(cur, str) and cur:
        return cur
    return None


def parse_publish_trust_config(manifest: dict[str, Any]) -> PublishTrustConfig:
    publish = manifest.get("publish")
    publish_obj = publish if isinstance(publish, dict) else {}

    trust_framework_obj = publish_obj.get("trust_framework")
    trust_framework = trust_framework_obj if isinstance(trust_framework_obj, dict) else {}

    auth = manifest.get("auth")
    auth_obj = auth if isinstance(auth, dict) else {}
    prm = auth_obj.get("prm")
    prm_obj = prm if isinstance(prm, dict) else {}

    signer_iss_hint = _get_nested_string(manifest, ["auth", "prm", "signed_metadata", "issuer"])
    if signer_iss_hint is None:
        signer_iss_hint = _get_nested_string(manifest, ["auth", "prm", "signed_metadata", "iss"])

    trust_framework_path = None
    tf_path_publish = trust_framework.get("path")
    if isinstance(tf_path_publish, str) and tf_path_publish:
        trust_framework_path = tf_path_publish
    else:
        tf_path_auth = _get_nested_string(manifest, ["auth", "prm", "trust_framework", "path"])
        if tf_path_auth:
            trust_framework_path = tf_path_auth

    trust_lock_path = None
    tf_lock_publish = trust_framework.get("trust_lock_path")
    if not isinstance(tf_lock_publish, str) or not tf_lock_publish:
        tf_lock_publish = trust_framework.get("lock_path")
    if isinstance(tf_lock_publish, str) and tf_lock_publish:
        trust_lock_path = tf_lock_publish
    else:
        tf_lock_auth = _get_nested_string(manifest, ["auth", "prm", "trust_framework", "trust_lock_path"])
        if tf_lock_auth is None:
            tf_lock_auth = _get_nested_string(manifest, ["auth", "prm", "trust_framework", "lock_path"])
        if tf_lock_auth:
            trust_lock_path = tf_lock_auth

    prm_path = _get_nested_string(manifest, ["publish", "prm", "path"]) or "publish/prm.json"
    resource_metadata_path = _get_nested_string(manifest, ["publish", "resource_metadata_path"]) or "/.well-known/oauth-protected-resource"

    require_signed_prm = bool(publish_obj.get("require_signed_prm", False))
    if not require_signed_prm and "require_signed_prm" in prm_obj:
        require_signed_prm = bool(prm_obj.get("require_signed_prm", False))

    emit_meta_summary = bool(trust_framework.get("emit_meta_summary", False))
    trust_pack_obj = trust_framework.get("trust_pack")
    trust_pack = trust_pack_obj if isinstance(trust_pack_obj, dict) else {}
    trust_pack_registry = None
    trust_pack_id = None
    trust_pack_version = None
    trust_pack_min_snapshot_version: int | None = None
    trust_pack_snapshot_sha256: str | None = None
    trust_pack_checkpoint_sha256: str | None = None
    trust_pack_root_path: str | None = None

    for cand in (
        trust_pack.get("registry"),
        trust_framework.get("trust_pack_registry"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_registry = cand
            break

    for cand in (
        trust_pack.get("pack_id"),
        trust_pack.get("packId"),
        trust_framework.get("trust_pack_id"),
        trust_framework.get("trust_packId"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_id = cand
            break

    for cand in (
        trust_pack.get("pack_version"),
        trust_pack.get("packVersion"),
        trust_framework.get("trust_pack_version"),
        trust_framework.get("trust_packVersion"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_version = cand
            break

    for cand in (
        trust_pack.get("min_snapshot_version"),
        trust_pack.get("minSnapshotVersion"),
        trust_framework.get("trust_pack_min_snapshot_version"),
        trust_framework.get("trust_packMinSnapshotVersion"),
    ):
        if isinstance(cand, int):
            trust_pack_min_snapshot_version = cand
            break

    for cand in (
        trust_pack.get("snapshot_sha256"),
        trust_pack.get("snapshotSha256"),
        trust_framework.get("trust_pack_snapshot_sha256"),
        trust_framework.get("trust_packSnapshotSha256"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_snapshot_sha256 = cand
            break

    for cand in (
        trust_pack.get("checkpoint_sha256"),
        trust_pack.get("checkpointSha256"),
        trust_framework.get("trust_pack_checkpoint_sha256"),
        trust_framework.get("trust_packCheckpointSha256"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_checkpoint_sha256 = cand
            break

    for cand in (
        trust_pack.get("root_path"),
        trust_pack.get("rootPath"),
        trust_framework.get("trust_pack_root_path"),
        trust_framework.get("trust_packRootPath"),
    ):
        if isinstance(cand, str) and cand:
            trust_pack_root_path = cand
            break

    return PublishTrustConfig(
        require_signed_prm=require_signed_prm,
        trust_framework_path=trust_framework_path,
        trust_lock_path=trust_lock_path,
        emit_meta_summary=emit_meta_summary,
        trust_pack_registry=trust_pack_registry,
        trust_pack_id=trust_pack_id,
        trust_pack_version=trust_pack_version,
        trust_pack_min_snapshot_version=trust_pack_min_snapshot_version,
        trust_pack_snapshot_sha256=trust_pack_snapshot_sha256,
        trust_pack_checkpoint_sha256=trust_pack_checkpoint_sha256,
        trust_pack_root_path=trust_pack_root_path,
        prm_path=prm_path,
        resource_metadata_path=resource_metadata_path,
        signer_iss_hint=signer_iss_hint,
    )


def _build_publish_meta_summary(
    *,
    require_signed: bool,
    framework_sha256: str,
    trust_lock_sha256: str,
    as_selection_strategy: str,
    trust_pack_registry: str | None = None,
    trust_pack_id: str | None = None,
    trust_pack_version: str | None = None,
    trust_pack_min_snapshot_version: int | None = None,
    trust_pack_snapshot_sha256: str | None = None,
    trust_pack_checkpoint_sha256: str | None = None,
) -> dict[str, Any]:
    if not SHA256_RE.fullmatch(framework_sha256):
        raise ValueError("trustFrameworkSha256 must match ^[0-9a-f]{64}$")
    if not SHA256_RE.fullmatch(trust_lock_sha256):
        raise ValueError("trustLockSha256 must match ^[0-9a-f]{64}$")
    if not isinstance(as_selection_strategy, str):
        raise ValueError("asSelectionStrategy must be a string")
    x07_summary: dict[str, Any] = {
        "trustFrameworkSha256": framework_sha256,
        "trustLockSha256": trust_lock_sha256,
        "requireSignedPrm": bool(require_signed),
        "asSelectionStrategy": as_selection_strategy,
    }

    if (
        trust_pack_registry
        or trust_pack_id
        or trust_pack_version
        or trust_pack_min_snapshot_version is not None
        or trust_pack_snapshot_sha256
        or trust_pack_checkpoint_sha256
    ):
        if not (
            trust_pack_registry
            and trust_pack_id
            and trust_pack_version
            and trust_pack_min_snapshot_version is not None
            and trust_pack_snapshot_sha256
            and trust_pack_checkpoint_sha256
        ):
            raise ValueError(
                "trustPack metadata requires registry, packId, packVersion, minSnapshotVersion, snapshotSha256, checkpointSha256"
            )
        if not _is_https_url_no_fragment(trust_pack_registry):
            raise ValueError("trustPack.registry must be HTTPS URL without fragment")
        if not isinstance(trust_pack_min_snapshot_version, int) or trust_pack_min_snapshot_version <= 0:
            raise ValueError("trustPack.minSnapshotVersion must be integer > 0")
        if (
            not isinstance(trust_pack_snapshot_sha256, str)
            or not SHA256_RE.fullmatch(trust_pack_snapshot_sha256)
            or trust_pack_snapshot_sha256 == PLACEHOLDER_SHA256
        ):
            raise ValueError("trustPack.snapshotSha256 must match ^[0-9a-f]{64}$ and not be placeholder")
        if (
            not isinstance(trust_pack_checkpoint_sha256, str)
            or not SHA256_RE.fullmatch(trust_pack_checkpoint_sha256)
            or trust_pack_checkpoint_sha256 == PLACEHOLDER_SHA256
        ):
            raise ValueError("trustPack.checkpointSha256 must match ^[0-9a-f]{64}$ and not be placeholder")
        x07_summary["trustPack"] = {
            "registry": trust_pack_registry,
            "packId": trust_pack_id,
            "packVersion": trust_pack_version,
            "lockSha256": trust_lock_sha256,
            "minSnapshotVersion": trust_pack_min_snapshot_version,
            "snapshotSha256": trust_pack_snapshot_sha256,
            "checkpointSha256": trust_pack_checkpoint_sha256,
        }

    return {"x07": x07_summary}


def _merge_publisher_meta_summary(server_doc: dict[str, Any], summary: dict[str, Any]) -> None:
    meta = server_doc.get("_meta")
    if meta is None:
        meta = {}
        server_doc["_meta"] = meta
    if not isinstance(meta, dict):
        raise ValueError("_meta must be an object")

    publisher = meta.get(ALLOWED_META_KEY)
    if publisher is None:
        publisher = {}
        meta[ALLOWED_META_KEY] = publisher
    if not isinstance(publisher, dict):
        raise ValueError("_meta publisher-provided must be an object")

    publisher.update(summary)


def infer_manifest_path_for_server_json(server_json_path: pathlib.Path) -> pathlib.Path | None:
    candidates = [
        server_json_path.parent / "x07.mcp.json",
        server_json_path.parent.parent / "x07.mcp.json",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def extract_publish_meta_x07(server_doc: dict[str, Any]) -> dict[str, Any] | None:
    meta = server_doc.get("_meta")
    if not isinstance(meta, dict):
        return None
    publisher = meta.get(ALLOWED_META_KEY)
    if not isinstance(publisher, dict):
        return None
    x07_meta = publisher.get("x07")
    if isinstance(x07_meta, dict):
        return x07_meta
    return None


def extract_publish_meta_prm_legacy(server_doc: dict[str, Any]) -> dict[str, Any] | None:
    meta = server_doc.get("_meta")
    if not isinstance(meta, dict):
        return None
    publisher = meta.get(ALLOWED_META_KEY)
    if not isinstance(publisher, dict):
        return None
    x07_mcp = publisher.get("x07.io/mcp")
    if not isinstance(x07_mcp, dict):
        return None
    prm = x07_mcp.get("prm")
    if isinstance(prm, dict):
        return prm
    return None


def _validate_publish_meta_x07(meta: dict[str, Any]) -> None:
    if "requireSignedPrm" in meta and not isinstance(meta["requireSignedPrm"], bool):
        raise ValueError("_meta publisher-provided x07.requireSignedPrm must be boolean")
    if "asSelectionStrategy" in meta and not isinstance(meta["asSelectionStrategy"], str):
        raise ValueError("_meta publisher-provided x07.asSelectionStrategy must be string")
    tf_sha = meta.get("trustFrameworkSha256")
    if tf_sha is not None and (not isinstance(tf_sha, str) or not SHA256_RE.fullmatch(tf_sha)):
        raise ValueError("_meta publisher-provided x07.trustFrameworkSha256 must match ^[0-9a-f]{64}$")
    lock_sha = meta.get("trustLockSha256")
    if lock_sha is not None and (not isinstance(lock_sha, str) or not SHA256_RE.fullmatch(lock_sha)):
        raise ValueError("_meta publisher-provided x07.trustLockSha256 must match ^[0-9a-f]{64}$")
    trust_pack = meta.get("trustPack")
    if trust_pack is not None:
        if not isinstance(trust_pack, dict):
            raise ValueError("_meta publisher-provided x07.trustPack must be object")
        registry = trust_pack.get("registry")
        if not isinstance(registry, str) or not registry or not _is_https_url_no_fragment(registry):
            raise ValueError("_meta publisher-provided x07.trustPack.registry must be HTTPS URL without fragment")
        pack_id = trust_pack.get("packId")
        if not isinstance(pack_id, str) or not pack_id:
            raise ValueError("_meta publisher-provided x07.trustPack.packId must be non-empty string")
        pack_version = trust_pack.get("packVersion")
        if not isinstance(pack_version, str) or not pack_version:
            raise ValueError("_meta publisher-provided x07.trustPack.packVersion must be non-empty string")
        lock_sha_pack = trust_pack.get("lockSha256")
        if (
            not isinstance(lock_sha_pack, str)
            or not SHA256_RE.fullmatch(lock_sha_pack)
            or lock_sha_pack == PLACEHOLDER_SHA256
        ):
            raise ValueError("_meta publisher-provided x07.trustPack.lockSha256 must match ^[0-9a-f]{64}$")
        min_snapshot_version = trust_pack.get("minSnapshotVersion")
        if not isinstance(min_snapshot_version, int) or min_snapshot_version <= 0:
            raise ValueError("_meta publisher-provided x07.trustPack.minSnapshotVersion must be integer > 0")
        snapshot_sha = trust_pack.get("snapshotSha256")
        if (
            not isinstance(snapshot_sha, str)
            or not SHA256_RE.fullmatch(snapshot_sha)
            or snapshot_sha == PLACEHOLDER_SHA256
        ):
            raise ValueError("_meta publisher-provided x07.trustPack.snapshotSha256 must match ^[0-9a-f]{64}$")
        checkpoint_sha = trust_pack.get("checkpointSha256")
        if (
            not isinstance(checkpoint_sha, str)
            or not SHA256_RE.fullmatch(checkpoint_sha)
            or checkpoint_sha == PLACEHOLDER_SHA256
        ):
            raise ValueError("_meta publisher-provided x07.trustPack.checkpointSha256 must match ^[0-9a-f]{64}$")


def _validate_publish_meta_prm_legacy(prm: dict[str, Any]) -> None:
    if "requireSigned" in prm and not isinstance(prm["requireSigned"], bool):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.requireSigned must be boolean")
    if "resourceMetadataPath" in prm and not isinstance(prm["resourceMetadataPath"], str):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.resourceMetadataPath must be string")
    if "signerIss" in prm and not isinstance(prm["signerIss"], str):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.signerIss must be string")
    tf_sha = prm.get("trustFrameworkSha256")
    if tf_sha is not None and (not isinstance(tf_sha, str) or not SHA256_RE.fullmatch(tf_sha)):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.trustFrameworkSha256 must match ^[0-9a-f]{64}$")


def generate_server_doc(
    manifest: dict[str, Any],
    schema_url: str,
    mcpb_sha256: str | None,
    manifest_path: pathlib.Path | None = None,
) -> dict[str, Any]:
    name = str(manifest.get("identifier", ""))
    if not name:
        raise ValueError("manifest identifier is required")
    if "mcp" not in name:
        raise ValueError("identifier must contain substring 'mcp'")

    version = str(manifest.get("version", ""))
    description = str(manifest.get("description", ""))
    if not version:
        raise ValueError("manifest version is required")
    if not description:
        raise ValueError("manifest description is required")

    out: dict[str, Any] = {
        "$schema": schema_url,
        "name": name,
        "version": version,
        "description": description,
    }

    title = manifest.get("display_name")
    if isinstance(title, str) and title:
        out["title"] = title

    if isinstance(manifest.get("_meta"), dict):
        out["_meta"] = manifest["_meta"]

    repository = manifest.get("repository")
    if isinstance(repository, dict):
        out["repository"] = repository

    website_url = manifest.get("websiteUrl")
    if isinstance(website_url, str) and website_url:
        out["websiteUrl"] = website_url

    packages_in = manifest.get("packages")
    if isinstance(packages_in, list) and packages_in:
        packages_out: list[dict[str, Any]] = []
        for pkg in packages_in:
            if not isinstance(pkg, dict):
                raise ValueError("package entry must be an object")
            registry_type = str(pkg.get("registryType", ""))
            identifier = str(pkg.get("identifier", ""))
            if not registry_type:
                raise ValueError("package registryType is required")
            if not identifier:
                raise ValueError("package identifier is required")
            if "mcp" not in identifier:
                raise ValueError("package identifier must contain substring 'mcp'")

            pkg_out: dict[str, Any] = {
                "registryType": registry_type,
                "identifier": identifier,
                "transport": _package_transport_from_input(pkg),
            }
            pkg_version = pkg.get("version")
            if isinstance(pkg_version, str) and pkg_version:
                pkg_out["version"] = pkg_version

            pkg_sha = pkg.get("fileSha256")
            if mcpb_sha256 and registry_type == "mcpb":
                pkg_sha = mcpb_sha256
            if isinstance(pkg_sha, str) and pkg_sha:
                pkg_out["fileSha256"] = pkg_sha

            packages_out.append(pkg_out)

        out["packages"] = packages_out

    remotes = manifest.get("remotes")
    if isinstance(remotes, list) and remotes:
        out["remotes"] = remotes

    if manifest_path is not None:
        cfg = parse_publish_trust_config(manifest)
        if cfg.emit_meta_summary:
            framework_sha = PLACEHOLDER_SHA256
            trust_lock_sha = PLACEHOLDER_SHA256
            as_strategy = "prefer_order_v1"
            if cfg.trust_framework_path:
                repo_root = _discover_repo_root(manifest_path)
                framework_path = _resolve_repo_relative_path(manifest_path.parent, cfg.trust_framework_path, repo_root)
                if not framework_path.is_file():
                    raise ValueError(f"trust framework file not found: {framework_path}")
                framework_doc = _load_trust_framework(framework_path)
                framework_sha = _framework_sha256_hex(framework_doc)
                as_strategy = _default_as_selection_strategy(framework_doc) or as_strategy
                if _framework_requires_signed_bundles(framework_doc) and not cfg.trust_lock_path:
                    raise ValueError(
                        f"{ERR_TRUST_PINS_MISSING}: publish.trust_framework.trust_lock_path is required for signed bundles"
                    )

            if cfg.trust_lock_path:
                repo_root = _discover_repo_root(manifest_path)
                trust_lock_path = _resolve_repo_relative_path(manifest_path.parent, cfg.trust_lock_path, repo_root)
                if not trust_lock_path.is_file():
                    raise ValueError(f"trust lock file not found: {trust_lock_path}")
                trust_lock_doc = _load_trust_lock(trust_lock_path)
                trust_lock_sha = _canonical_sha256_hex(trust_lock_doc)

            trust_pack_enabled = bool(
                cfg.trust_pack_registry
                or cfg.trust_pack_id
                or cfg.trust_pack_version
                or cfg.trust_pack_min_snapshot_version is not None
                or cfg.trust_pack_snapshot_sha256
                or cfg.trust_pack_checkpoint_sha256
                or cfg.trust_pack_root_path
            )

            if trust_pack_enabled and trust_lock_sha == PLACEHOLDER_SHA256:
                raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust pack metadata requires trust lock sha")
            if trust_pack_enabled and not cfg.trust_pack_root_path:
                raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust pack metadata requires trust_pack.root_path")
            if trust_pack_enabled and cfg.trust_pack_root_path:
                repo_root = _discover_repo_root(manifest_path)
                trust_pack_root_path = _resolve_repo_relative_path(
                    manifest_path.parent, cfg.trust_pack_root_path, repo_root
                )
                if not trust_pack_root_path.is_file():
                    raise ValueError(f"trust pack root file not found: {trust_pack_root_path}")
                trust_pack_root_doc = read_json(trust_pack_root_path)
                trust_pack_root_obj = _as_object(
                    trust_pack_root_doc, field=f"trust pack root file {trust_pack_root_path}"
                )
                _validate_registry_root_doc(
                    trust_pack_root_obj, field_prefix=f"trust pack root {trust_pack_root_path}"
                )

            summary = _build_publish_meta_summary(
                require_signed=cfg.require_signed_prm,
                framework_sha256=framework_sha,
                trust_lock_sha256=trust_lock_sha,
                as_selection_strategy=as_strategy,
                trust_pack_registry=cfg.trust_pack_registry,
                trust_pack_id=cfg.trust_pack_id,
                trust_pack_version=cfg.trust_pack_version,
                trust_pack_min_snapshot_version=cfg.trust_pack_min_snapshot_version,
                trust_pack_snapshot_sha256=cfg.trust_pack_snapshot_sha256,
                trust_pack_checkpoint_sha256=cfg.trust_pack_checkpoint_sha256,
            )
            _merge_publisher_meta_summary(out, summary)

    return out


def validate_non_schema_constraints(doc: dict[str, Any]) -> None:
    name = str(doc.get("name", ""))
    if "mcp" not in name:
        raise ValueError("name must contain substring 'mcp'")

    packages = doc.get("packages")
    if isinstance(packages, list):
        for pkg in packages:
            if not isinstance(pkg, dict):
                raise ValueError("package entry must be an object")
            identifier = str(pkg.get("identifier", ""))
            if not identifier:
                raise ValueError("package identifier is required")
            if "mcp" not in identifier:
                raise ValueError("package identifier must contain substring 'mcp'")

            registry_type = str(pkg.get("registryType", ""))
            if registry_type == "mcpb":
                sha = str(pkg.get("fileSha256", ""))
                if not sha:
                    raise ValueError("mcpb package requires fileSha256")
                if not SHA256_RE.fullmatch(sha):
                    raise ValueError("mcpb package fileSha256 must match ^[0-9a-f]{64}$")

    meta = doc.get("_meta")
    if meta is not None:
        if not isinstance(meta, dict):
            raise ValueError("_meta must be an object")
        keys = list(meta.keys())
        if any(key != ALLOWED_META_KEY for key in keys):
            raise ValueError("_meta contains unsupported keys")

        publisher = meta.get(ALLOWED_META_KEY)
        if publisher is not None and not isinstance(publisher, dict):
            raise ValueError("_meta publisher-provided must be an object")

        x07_meta = extract_publish_meta_x07(doc)
        if x07_meta is not None:
            _validate_publish_meta_x07(x07_meta)
        prm_legacy = extract_publish_meta_prm_legacy(doc)
        if prm_legacy is not None:
            _validate_publish_meta_prm_legacy(prm_legacy)

        if len(json.dumps(meta, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")) > 4096:
            raise ValueError("_meta exceeds 4096 bytes")


def validate_schema(doc: dict[str, Any], schema_path: pathlib.Path) -> None:
    schema = read_json(schema_path)
    try:
        from jsonschema import Draft7Validator
    except Exception as exc:
        raise RuntimeError(f"jsonschema module unavailable: {exc}") from exc
    validator = Draft7Validator(schema)
    errors = sorted(validator.iter_errors(doc), key=lambda err: list(err.path))
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.path)
        raise ValueError(f"schema validation failed at '{path}': {first.message}")


def verify_publish_trust_policy(
    *,
    server_doc: dict[str, Any],
    server_json_path: pathlib.Path,
    manifest_path: pathlib.Path | None,
    prm_path_override: pathlib.Path | None,
    trust_framework_path_override: pathlib.Path | None,
) -> tuple[dict[str, Any] | None, pathlib.Path | None]:
    manifest_candidate = manifest_path or infer_manifest_path_for_server_json(server_json_path)
    if manifest_candidate is None:
        return None, None

    manifest_doc = read_json(manifest_candidate)
    if not isinstance(manifest_doc, dict):
        raise ValueError("manifest must be a JSON object")

    cfg = parse_publish_trust_config(manifest_doc)
    if not cfg.require_signed_prm and not cfg.emit_meta_summary:
        return None, manifest_candidate

    repo_root = _discover_repo_root(manifest_candidate)
    tf_path: pathlib.Path | None = trust_framework_path_override
    if tf_path is None and cfg.trust_framework_path:
        tf_path = _resolve_repo_relative_path(manifest_candidate.parent, cfg.trust_framework_path, repo_root)

    if cfg.require_signed_prm and tf_path is None:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust framework path is required when require_signed_prm=true")

    loaded: LoadedTrustFramework | None = None
    framework_sha = PLACEHOLDER_SHA256
    trust_lock_sha = PLACEHOLDER_SHA256
    as_selection_strategy = "prefer_order_v1"
    if tf_path is not None:
        if not tf_path.is_file():
            raise ValueError(f"trust framework file not found: {tf_path}")
        loaded = load_trust_framework_with_bundles(tf_path, repo_root=repo_root)
        framework_sha = _framework_sha256_hex(loaded.framework)
        as_selection_strategy = _default_as_selection_strategy(loaded.framework) or as_selection_strategy

        trust_lock_path: pathlib.Path | None = None
        if cfg.trust_lock_path:
            trust_lock_path = _resolve_repo_relative_path(manifest_candidate.parent, cfg.trust_lock_path, repo_root)
        trust_lock_sha, _ = _verify_framework_bundles_with_lock(loaded, trust_lock_path=trust_lock_path)

    prm_path = prm_path_override
    if prm_path is None:
        prm_path = _resolve_repo_relative_path(manifest_candidate.parent, cfg.prm_path, repo_root)

    if cfg.require_signed_prm and not prm_path.is_file():
        raise ValueError(f"{ERR_PRM_UNSIGNED}: PRM file not found: {prm_path}")

    if prm_path.is_file() and loaded is not None:
        prm_doc = read_json(prm_path)
        if not isinstance(prm_doc, dict):
            raise ValueError("PRM must be a JSON object")

        resource = prm_doc.get("resource")
        if not isinstance(resource, str) or not resource:
            resource = ""

        as_policy: dict[str, Any] | None = None
        if resource:
            as_policy = resolve_as_policy(loaded.framework, resource)

        signed_metadata = prm_doc.get("signed_metadata")
        if cfg.require_signed_prm and not isinstance(signed_metadata, str):
            raise ValueError(f"{ERR_PRM_UNSIGNED}: signed_metadata is required")

        if isinstance(signed_metadata, str):
            _, pre_payload, _, _ = _parse_jwt_compact(signed_metadata)
            iss = pre_payload.get("iss")
            if not isinstance(iss, str) or not iss:
                raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signed_metadata payload missing iss")

            resource_from_signed = pre_payload.get("resource")
            if isinstance(resource_from_signed, str) and resource_from_signed:
                resource = resource_from_signed
            if not resource:
                raise ValueError(f"{ERR_TRUST_POLICY_MISSING}: PRM resource is required")

            policy = resolve_prm_signed_policy(loaded.framework, resource)
            if not policy["matched"] and bool(policy["require_signed_prm"]):
                raise ValueError(f"{ERR_TRUST_POLICY_MISSING}: no trust policy matched resource {resource}")

            allowed_issuers = policy.get("allowed_prm_signers", [])
            if isinstance(allowed_issuers, list) and allowed_issuers:
                if iss not in allowed_issuers:
                    raise ValueError(f"{ERR_TRUST_ISSUER_NOT_ALLOWED}: issuer {iss} is not allowed for resource {resource}")

            keys, issuer_algs = trust_keys_for_issuer(loaded, iss)
            if not keys:
                raise ValueError(f"{ERR_TRUST_PINS_MISSING}: no pinned JWKS keys found for issuer {iss}")

            verify_cfg = policy.get("verify_cfg")
            verify_obj = verify_cfg if isinstance(verify_cfg, dict) else {}
            allowed_algs = verify_obj.get("allowed_algs")
            if not isinstance(allowed_algs, list) or not allowed_algs:
                allowed_algs = issuer_algs
            if not isinstance(allowed_algs, list):
                allowed_algs = []
            max_clock_skew = int(verify_obj.get("max_clock_skew_seconds", 60))

            _verify_signed_metadata_with_keys(
                signed_metadata,
                keys=keys,
                allowed_algs=[str(a) for a in allowed_algs if isinstance(a, str)],
                max_clock_skew_seconds=max_clock_skew,
                context="signed_metadata",
            )

            as_policy = resolve_as_policy(loaded.framework, resource)

        if as_policy is not None:
            auth_servers_any = prm_doc.get("authorization_servers")
            auth_servers: list[str] = []
            if isinstance(auth_servers_any, list):
                auth_servers = [x for x in auth_servers_any if isinstance(x, str)]
            if not auth_servers:
                raise ValueError(f"{ERR_TRUST_POLICY_MISSING}: PRM authorization_servers is required for AS selection")
            selection = select_authorization_server_v1(as_policy, auth_servers)
            selected_issuer = str(selection.get("selected_issuer", ""))
            if not selected_issuer:
                raise ValueError("as_no_allowed_issuer")
            as_selection_strategy = str(as_policy.get("strategy", as_selection_strategy)) or as_selection_strategy

    trust_pack_enabled = bool(
        cfg.trust_pack_registry
        or cfg.trust_pack_id
        or cfg.trust_pack_version
        or cfg.trust_pack_min_snapshot_version is not None
        or cfg.trust_pack_snapshot_sha256
        or cfg.trust_pack_checkpoint_sha256
        or cfg.trust_pack_root_path
    )

    if trust_pack_enabled and trust_lock_sha == PLACEHOLDER_SHA256:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust pack metadata requires trust lock sha")
    if trust_pack_enabled and not cfg.trust_pack_root_path:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: trust pack metadata requires trust_pack.root_path")
    if trust_pack_enabled and cfg.trust_pack_root_path:
        trust_pack_root_path = _resolve_repo_relative_path(
            manifest_candidate.parent, cfg.trust_pack_root_path, repo_root
        )
        if not trust_pack_root_path.is_file():
            raise ValueError(f"trust pack root file not found: {trust_pack_root_path}")
        trust_pack_root_doc = read_json(trust_pack_root_path)
        trust_pack_root_obj = _as_object(trust_pack_root_doc, field=f"trust pack root file {trust_pack_root_path}")
        _validate_registry_root_doc(trust_pack_root_obj, field_prefix=f"trust pack root {trust_pack_root_path}")

    summary = _build_publish_meta_summary(
        require_signed=cfg.require_signed_prm,
        framework_sha256=framework_sha,
        trust_lock_sha256=trust_lock_sha,
        as_selection_strategy=as_selection_strategy,
        trust_pack_registry=cfg.trust_pack_registry,
        trust_pack_id=cfg.trust_pack_id,
        trust_pack_version=cfg.trust_pack_version,
        trust_pack_min_snapshot_version=cfg.trust_pack_min_snapshot_version,
        trust_pack_snapshot_sha256=cfg.trust_pack_snapshot_sha256,
        trust_pack_checkpoint_sha256=cfg.trust_pack_checkpoint_sha256,
    )

    if cfg.emit_meta_summary:
        x07_meta = extract_publish_meta_x07(server_doc)
        if x07_meta is None:
            raise ValueError(f"{ERR_TRUST_META_MISMATCH}: server.json missing _meta publisher trust summary")

        want_meta = _get_nested_object(summary, ["x07"]) or {}
        for key, want in want_meta.items():
            got = x07_meta.get(key)
            if got != want:
                raise ValueError(
                    f"{ERR_TRUST_META_MISMATCH}: server.json trust summary mismatch for {key} (got={got!r} want={want!r})"
                )

    return summary, manifest_candidate


def parse_common_schema_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--schema", dest="schema_file", default=PIN_SCHEMA_FILE)
    parser.add_argument("--schema-url", dest="schema_url", default=PIN_SCHEMA_URL)
