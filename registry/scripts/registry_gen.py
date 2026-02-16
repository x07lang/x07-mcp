#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys

from registry_lib import (
    canonical_json_text,
    generate_server_doc,
    parse_common_schema_args,
    read_json,
    sha256_file,
    validate_non_schema_constraints,
    validate_schema,
    write_canonical_json,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate deterministic MCP registry server.json")
    parser.add_argument("--in", dest="input_path", required=True)
    parser.add_argument("--out", dest="output_path", required=True)
    parser.add_argument("--mcpb", dest="mcpb_path")
    parser.add_argument("--machine", choices=["json"], default=None)
    parse_common_schema_args(parser)
    args = parser.parse_args()

    input_path = pathlib.Path(args.input_path)
    output_path = pathlib.Path(args.output_path)
    schema_path = pathlib.Path(args.schema_file)
    mcpb_sha = None
    if args.mcpb_path:
        mcpb_sha = sha256_file(pathlib.Path(args.mcpb_path))

    try:
        manifest = read_json(input_path)
        server_doc = generate_server_doc(manifest, args.schema_url, mcpb_sha)
        validate_schema(server_doc, schema_path)
        validate_non_schema_constraints(server_doc)
        write_canonical_json(output_path, server_doc)
    except Exception as exc:
        if args.machine == "json":
            sys.stdout.write(canonical_json_text({"ok": False, "error": str(exc)}))
        else:
            sys.stderr.write(f"error: {exc}\n")
        return 1

    if args.machine == "json":
        sys.stdout.write(canonical_json_text({"ok": True, "out": str(output_path)}))
    else:
        sys.stdout.write(f"ok: wrote {output_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
