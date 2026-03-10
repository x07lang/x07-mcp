#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

from stdio_smoke_lib import build_bins, expected_server_version, run_stdio_smoke


def main() -> int:
    server_root = Path(__file__).resolve().parents[1]
    build_bins(server_root)

    router_bin = server_root / "out" / "x07lang-mcp"
    if not router_bin.is_file():
        raise RuntimeError(f"missing router binary: {router_bin}")
    fixture_root = server_root / "tests" / "fixtures" / "search_ws"
    run_stdio_smoke(
        router_bin,
        server_root,
        fixture_root,
        expected_server_version(server_root),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
