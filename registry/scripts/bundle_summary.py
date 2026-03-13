#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys

from workbench_summary import canonical_json_text, compute_bundle_summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit MCP bundle summary for Forge workbench consumers")
    parser.add_argument("--server-dir", required=True)
    parser.add_argument("--mcpb", required=True)
    parser.add_argument("--server-json")
    parser.add_argument("--machine", choices=["json"], default=None)
    args = parser.parse_args()

    summary = compute_bundle_summary(
        server_dir=pathlib.Path(args.server_dir),
        mcpb_path=pathlib.Path(args.mcpb),
        server_json_path=pathlib.Path(args.server_json) if args.server_json else None,
    )

    if args.machine == "json":
        sys.stdout.write(canonical_json_text(summary))
    else:
        sys.stdout.write(f"{summary['bundle']['path']}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
