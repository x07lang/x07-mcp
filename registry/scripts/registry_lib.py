#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
from typing import Any


PIN_SCHEMA_URL = "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json"
PIN_SCHEMA_FILE = "registry/schema/server.schema.2025-12-11.json"
ALLOWED_META_KEY = "io.modelcontextprotocol.registry/publisher-provided"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


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


def generate_server_doc(
    manifest: dict[str, Any],
    schema_url: str,
    mcpb_sha256: str | None,
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


def parse_common_schema_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--schema", dest="schema_file", default=PIN_SCHEMA_FILE)
    parser.add_argument("--schema-url", dest="schema_url", default=PIN_SCHEMA_URL)
