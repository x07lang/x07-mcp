#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys

from registry_lib import (
    PIN_SCHEMA_URL,
    canonical_json_text,
    parse_common_schema_args,
    read_json,
    sha256_file,
    validate_non_schema_constraints,
    validate_schema,
)


def _first_mcpb_package(server_doc: dict) -> dict | None:
    packages = server_doc.get("packages")
    if not isinstance(packages, list):
        return None
    for pkg in packages:
        if isinstance(pkg, dict) and str(pkg.get("registryType", "")) == "mcpb":
            return pkg
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate server.json + .mcpb for publish dry-run")
    parser.add_argument("--server-json", required=True)
    parser.add_argument("--mcpb", required=True)
    parser.add_argument("--machine", choices=["json"], default=None)
    parse_common_schema_args(parser)
    args = parser.parse_args()

    server_json_path = pathlib.Path(args.server_json)
    mcpb_path = pathlib.Path(args.mcpb)
    schema_path = pathlib.Path(args.schema_file)

    try:
        if not mcpb_path.is_file():
            raise ValueError(f"missing mcpb file: {mcpb_path}")

        server_doc = read_json(server_json_path)
        if str(server_doc.get("$schema", "")) != args.schema_url:
            raise ValueError(f"server.json $schema must be {args.schema_url}")
        if str(server_doc.get("$schema", "")) != PIN_SCHEMA_URL:
            raise ValueError(f"server.json $schema must match pinned URL {PIN_SCHEMA_URL}")

        validate_schema(server_doc, schema_path)
        validate_non_schema_constraints(server_doc)

        mcpb_pkg = _first_mcpb_package(server_doc)
        if mcpb_pkg is None:
            raise ValueError("server.json must include at least one mcpb package")
        file_sha = str(mcpb_pkg.get("fileSha256", ""))
        if not file_sha:
            raise ValueError("mcpb package is missing fileSha256")

        actual_sha = sha256_file(mcpb_path)
        if actual_sha != file_sha:
            raise ValueError(f"mcpb sha mismatch: expected {file_sha}, got {actual_sha}")
    except Exception as exc:
        if args.machine == "json":
            sys.stdout.write(canonical_json_text({"ok": False, "error": str(exc)}))
        else:
            sys.stderr.write(f"error: {exc}\n")
        return 1

    if args.machine == "json":
        sys.stdout.write(canonical_json_text({"ok": True, "server_json": str(server_json_path), "mcpb": str(mcpb_path)}))
    else:
        sys.stdout.write("ok: publish dry-run validation passed\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
