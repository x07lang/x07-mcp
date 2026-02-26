#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
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
TRUST_FRAMEWORK_SCHEMA = "x07.mcp.trust.framework@0.1.0"

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
    emit_meta_summary: bool
    prm_path: str
    resource_metadata_path: str
    signer_iss_hint: str | None


@dataclass(frozen=True)
class LoadedTrustFramework:
    path: pathlib.Path
    repo_root: pathlib.Path
    framework: dict[str, Any]
    bundles: list[dict[str, Any]]


def read_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_canonical_json(path: pathlib.Path, doc: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        handle.write(canonical_json_text(doc))


def canonical_json_text(doc: Any) -> str:
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


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
    canon = canonical_json_text(framework_doc).encode("utf-8")
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


def _parse_jwt_compact(token: str) -> tuple[dict[str, Any], dict[str, Any], bytes, bytes]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("signed_metadata must be a compact JWS")
    h_raw, p_raw, s_raw = parts
    try:
        header = json.loads(_b64u_decode(h_raw).decode("utf-8"))
        payload = json.loads(_b64u_decode(p_raw).decode("utf-8"))
    except Exception as exc:
        raise ValueError("signed_metadata header/payload must be valid JSON") from exc
    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise ValueError("signed_metadata header/payload must be JSON objects")
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


def _verify_ed25519_openssl(signing_input: bytes, signature: bytes, jwk: dict[str, Any]) -> bool:
    if shutil.which("openssl") is None:
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

        proc = subprocess.run(
            [
                "openssl",
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
        return proc.returncode == 0


def _verify_signed_metadata_with_keys(
    token: str,
    *,
    keys: list[dict[str, Any]],
    allowed_algs: list[str],
    max_clock_skew_seconds: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    header, payload, signing_input, signature = _parse_jwt_compact(token)

    alg = header.get("alg")
    if not isinstance(alg, str) or not alg:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signed_metadata header missing alg")
    if alg == "none":
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: alg=none is not allowed")
    if allowed_algs and alg not in allowed_algs:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: alg {alg} is not allowed by trust policy")

    now_s = int(__import__("time").time())
    skew = max(0, max_clock_skew_seconds)
    exp = _jwt_int_claim(payload, "exp")
    nbf = _jwt_int_claim(payload, "nbf")
    if exp is not None and now_s > exp + skew:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signed_metadata is expired")
    if nbf is not None and now_s + skew < nbf:
        raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signed_metadata is not yet valid")

    kid = header.get("kid")
    candidates = keys
    if isinstance(kid, str) and kid:
        candidates = [k for k in keys if str(k.get("kid", "")) == kid]

    if not candidates:
        raise ValueError(f"{ERR_TRUST_PINS_MISSING}: no pinned key matches signed_metadata kid")

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

        algs = _as_array(issuer_doc.get("algs"), field=f"{field_prefix}.issuers[{idx}].algs")
        if not algs:
            raise ValueError(f"{field_prefix}.issuers[{idx}].algs must not be empty")
        for j, alg in enumerate(algs):
            _as_nonempty_string(alg, field=f"{field_prefix}.issuers[{idx}].algs[{j}]")

        jwks_doc = _as_object(issuer_doc.get("jwks"), field=f"{field_prefix}.issuers[{idx}].jwks")
        keys = _as_array(jwks_doc.get("keys"), field=f"{field_prefix}.issuers[{idx}].jwks.keys")
        if not keys:
            raise ValueError(f"{field_prefix}.issuers[{idx}].jwks.keys must not be empty")
        for key_idx, key_any in enumerate(keys):
            jwk = _as_object(key_any, field=f"{field_prefix}.issuers[{idx}].jwks.keys[{key_idx}]")
            _validate_jwk_for_trust(jwk, field_prefix=f"{field_prefix}.issuers[{idx}].jwks.keys[{key_idx}]")


def _validate_trust_framework(framework: dict[str, Any], *, field_prefix: str = "framework") -> None:
    schema_version = _as_nonempty_string(framework.get("schema_version"), field=f"{field_prefix}.schema_version")
    if schema_version != TRUST_FRAMEWORK_SCHEMA:
        raise ValueError(f"{field_prefix}.schema_version must be {TRUST_FRAMEWORK_SCHEMA}")

    bundles = _as_array(framework.get("bundles"), field=f"{field_prefix}.bundles")
    if not bundles:
        raise ValueError(f"{field_prefix}.bundles must not be empty")
    for idx, bundle_ref_any in enumerate(bundles):
        bundle_ref = _as_object(bundle_ref_any, field=f"{field_prefix}.bundles[{idx}]")
        path_txt = _as_nonempty_string(bundle_ref.get("path"), field=f"{field_prefix}.bundles[{idx}].path")
        if pathlib.Path(path_txt).is_absolute():
            raise ValueError(f"{field_prefix}.bundles[{idx}].path must be relative")

    policies = framework.get("resource_policies")
    if policies is not None:
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
                    raise ValueError(
                        f"{field_prefix}.resource_policies[{idx}].allowed_prm_signers[{signer_idx}] must be HTTPS URL"
                    )

            verify_cfg = policy.get("verify_cfg")
            if verify_cfg is not None:
                verify = _as_object(verify_cfg, field=f"{field_prefix}.resource_policies[{idx}].verify_cfg")
                mode = verify.get("mode")
                if mode is not None and mode not in {"fail_closed", "best_effort"}:
                    raise ValueError(f"{field_prefix}.resource_policies[{idx}].verify_cfg.mode invalid: {mode}")
                allowed_algs = verify.get("allowed_algs")
                if allowed_algs is not None:
                    arr = _as_array(allowed_algs, field=f"{field_prefix}.resource_policies[{idx}].verify_cfg.allowed_algs")
                    if not arr:
                        raise ValueError(
                            f"{field_prefix}.resource_policies[{idx}].verify_cfg.allowed_algs must not be empty"
                        )
                    for alg_idx, alg in enumerate(arr):
                        _as_nonempty_string(
                            alg,
                            field=f"{field_prefix}.resource_policies[{idx}].verify_cfg.allowed_algs[{alg_idx}]",
                        )


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
    for idx, bundle_ref_any in enumerate(_as_array(framework.get("bundles"), field="framework.bundles")):
        bundle_ref = _as_object(bundle_ref_any, field=f"framework.bundles[{idx}]")
        rel = _as_nonempty_string(bundle_ref.get("path"), field=f"framework.bundles[{idx}].path")
        bundle_path = _resolve_repo_relative_path(framework_path.parent, rel, repo)
        if not bundle_path.is_file():
            raise ValueError(f"trust bundle file not found: {bundle_path}")
        bundles.append(_load_trust_bundle(bundle_path))

    return LoadedTrustFramework(path=framework_path, repo_root=repo, framework=framework, bundles=bundles)


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


def trust_keys_for_issuer(loaded: LoadedTrustFramework, issuer: str) -> tuple[list[dict[str, Any]], list[str]]:
    keys: list[dict[str, Any]] = []
    allowed_algs: list[str] = []

    for bundle in loaded.bundles:
        issuers = _as_array(bundle.get("issuers"), field="bundle.issuers")
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

    deduped_keys: list[dict[str, Any]] = []
    seen: set[str] = set()
    for jwk in keys:
        marker = canonical_json_text(jwk)
        if marker in seen:
            continue
        seen.add(marker)
        deduped_keys.append(jwk)

    return deduped_keys, _stable_unique(allowed_algs)


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

    prm_path = _get_nested_string(manifest, ["publish", "prm", "path"]) or "publish/prm.json"
    resource_metadata_path = _get_nested_string(manifest, ["publish", "resource_metadata_path"]) or "/.well-known/oauth-protected-resource"

    require_signed_prm = bool(publish_obj.get("require_signed_prm", False))
    if not require_signed_prm and "require_signed_prm" in prm_obj:
        require_signed_prm = bool(prm_obj.get("require_signed_prm", False))

    emit_meta_summary = bool(trust_framework.get("emit_meta_summary", False))

    return PublishTrustConfig(
        require_signed_prm=require_signed_prm,
        trust_framework_path=trust_framework_path,
        emit_meta_summary=emit_meta_summary,
        prm_path=prm_path,
        resource_metadata_path=resource_metadata_path,
        signer_iss_hint=signer_iss_hint,
    )


def _build_publish_meta_summary(
    *,
    require_signed: bool,
    resource_metadata_path: str,
    signer_iss: str,
    framework_sha256: str,
) -> dict[str, Any]:
    if not isinstance(resource_metadata_path, str) or not resource_metadata_path:
        raise ValueError("resourceMetadataPath must be non-empty")
    if not SHA256_RE.fullmatch(framework_sha256):
        raise ValueError("trustFrameworkSha256 must match ^[0-9a-f]{64}$")
    return {
        "x07.io/mcp": {
            "prm": {
                "requireSigned": bool(require_signed),
                "resourceMetadataPath": resource_metadata_path,
                "signerIss": signer_iss,
                "trustFrameworkSha256": framework_sha256,
            }
        }
    }


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


def extract_publish_meta_prm(server_doc: dict[str, Any]) -> dict[str, Any] | None:
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


def _validate_publish_meta_prm(prm: dict[str, Any]) -> None:
    if "requireSigned" in prm and not isinstance(prm["requireSigned"], bool):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.requireSigned must be boolean")
    if "resourceMetadataPath" in prm and not isinstance(prm["resourceMetadataPath"], str):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.resourceMetadataPath must be string")
    if "signerIss" in prm and not isinstance(prm["signerIss"], str):
        raise ValueError("_meta publisher-provided x07.io/mcp.prm.signerIss must be string")
    tf_sha = prm.get("trustFrameworkSha256")
    if tf_sha is not None:
        if not isinstance(tf_sha, str) or not SHA256_RE.fullmatch(tf_sha):
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
            if cfg.trust_framework_path:
                repo_root = _discover_repo_root(manifest_path)
                framework_path = _resolve_repo_relative_path(manifest_path.parent, cfg.trust_framework_path, repo_root)
                if not framework_path.is_file():
                    raise ValueError(f"trust framework file not found: {framework_path}")
                framework_doc = _load_trust_framework(framework_path)
                framework_sha = _framework_sha256_hex(framework_doc)

            summary = _build_publish_meta_summary(
                require_signed=cfg.require_signed_prm,
                resource_metadata_path=cfg.resource_metadata_path,
                signer_iss=cfg.signer_iss_hint or "",
                framework_sha256=framework_sha,
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

        prm = extract_publish_meta_prm(doc)
        if prm is not None:
            _validate_publish_meta_prm(prm)

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
    if tf_path is not None:
        if not tf_path.is_file():
            raise ValueError(f"trust framework file not found: {tf_path}")
        loaded = load_trust_framework_with_bundles(tf_path, repo_root=repo_root)
        framework_sha = _framework_sha256_hex(loaded.framework)

    prm_path = prm_path_override
    if prm_path is None:
        prm_path = _resolve_repo_relative_path(manifest_candidate.parent, cfg.prm_path, repo_root)

    if cfg.require_signed_prm and not prm_path.is_file():
        raise ValueError(f"{ERR_PRM_UNSIGNED}: PRM file not found: {prm_path}")

    signer_iss = cfg.signer_iss_hint or ""
    if prm_path.is_file() and loaded is not None:
        prm_doc = read_json(prm_path)
        if not isinstance(prm_doc, dict):
            raise ValueError("PRM must be a JSON object")

        signed_metadata = prm_doc.get("signed_metadata")
        if cfg.require_signed_prm and not isinstance(signed_metadata, str):
            raise ValueError(f"{ERR_PRM_UNSIGNED}: signed_metadata is required")

        if isinstance(signed_metadata, str):
            pre_header, pre_payload, _, _ = _parse_jwt_compact(signed_metadata)
            iss = pre_payload.get("iss")
            if not isinstance(iss, str) or not iss:
                raise ValueError(f"{ERR_PRM_SIGNATURE_INVALID}: signed_metadata payload missing iss")
            signer_iss = iss

            resource = pre_payload.get("resource")
            if not isinstance(resource, str) or not resource:
                resource_from_prm = prm_doc.get("resource")
                if isinstance(resource_from_prm, str) and resource_from_prm:
                    resource = resource_from_prm
            if not isinstance(resource, str) or not resource:
                raise ValueError(f"{ERR_TRUST_POLICY_MISSING}: PRM resource is required")

            policy = resolve_trust_policy(loaded.framework, resource)
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
            )

    summary = _build_publish_meta_summary(
        require_signed=cfg.require_signed_prm,
        resource_metadata_path=cfg.resource_metadata_path,
        signer_iss=signer_iss,
        framework_sha256=framework_sha,
    )

    if cfg.emit_meta_summary:
        prm_meta = extract_publish_meta_prm(server_doc)
        if prm_meta is None:
            raise ValueError(f"{ERR_TRUST_META_MISMATCH}: server.json missing _meta publisher trust summary")

        want_prm = _get_nested_object(summary, ["x07.io/mcp", "prm"]) or {}
        for key, want in want_prm.items():
            got = prm_meta.get(key)
            if got != want:
                raise ValueError(
                    f"{ERR_TRUST_META_MISMATCH}: server.json trust summary mismatch for {key} (got={got!r} want={want!r})"
                )

    return summary, manifest_candidate


def parse_common_schema_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--schema", dest="schema_file", default=PIN_SCHEMA_FILE)
    parser.add_argument("--schema-url", dest="schema_url", default=PIN_SCHEMA_URL)
