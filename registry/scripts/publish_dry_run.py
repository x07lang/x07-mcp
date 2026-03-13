#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys

from registry_lib import PIN_SCHEMA_URL, parse_common_schema_args, write_canonical_json
from workbench_summary import canonical_json_text, compute_publish_readiness


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate server.json + .mcpb for publish dry-run")
    parser.add_argument("--server-json", required=True)
    parser.add_argument("--mcpb", required=True)
    parser.add_argument("--manifest")
    parser.add_argument("--prm")
    parser.add_argument("--trust-framework")
    parser.add_argument("--machine", choices=["json"], default=None)
    parse_common_schema_args(parser)
    args = parser.parse_args()

    server_json_path = pathlib.Path(args.server_json)
    mcpb_path = pathlib.Path(args.mcpb)
    schema_path = pathlib.Path(args.schema_file)
    manifest_path = pathlib.Path(args.manifest).resolve() if args.manifest else None
    prm_path = pathlib.Path(args.prm).resolve() if args.prm else None
    trust_framework_path = pathlib.Path(args.trust_framework).resolve() if args.trust_framework else None

    if args.schema_url != PIN_SCHEMA_URL:
        raise SystemExit(f"error: schema_url must match pinned URL {PIN_SCHEMA_URL}\n")

    summary, trust_summary, resolved_manifest_path = compute_publish_readiness(
        server_json_path=server_json_path,
        mcpb_path=mcpb_path,
        schema_path=schema_path,
        schema_url=args.schema_url,
        manifest_path_override=manifest_path,
        prm_path_override=prm_path,
        trust_framework_path_override=trust_framework_path,
    )

    if summary.get("ok") and trust_summary is not None and resolved_manifest_path is not None:
        meta_summary_path = resolved_manifest_path.parent / "publish" / "meta_summary.json"
        write_canonical_json(meta_summary_path, trust_summary)

    if args.machine == "json":
        sys.stdout.write(canonical_json_text(summary))
    elif summary.get("ok"):
        sys.stdout.write("ok: publish dry-run validation passed\n")
    else:
        first_blocker = next(iter(summary.get("blockers") or []), {})
        message = str(first_blocker.get("message", "publish dry-run failed"))
        sys.stderr.write(f"error: {message}\n")

    return 0 if summary.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
