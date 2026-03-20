#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import zipfile
from pathlib import Path

from stdio_smoke_lib import (
    build_bundle,
    expected_server_version,
    run_fmt_path_resolution_smoke,
    run_stdio_smoke,
)


def main() -> int:
    server_root = Path(__file__).resolve().parents[1]
    bundle_path = build_bundle(server_root)
    want_version = expected_server_version(server_root)
    fixture_root = server_root / "tests" / "fixtures" / "search_ws"

    with tempfile.TemporaryDirectory(prefix="x07lang-mcp-bundle-smoke-") as tmp_dir:
        extracted_root = Path(tmp_dir)
        with zipfile.ZipFile(bundle_path, "r") as bundle_zip:
            bundle_zip.extractall(extracted_root)
        server_exe = extracted_root / "server" / "x07lang-mcp"
        worker_exe = extracted_root / "out" / "mcp-worker"
        if not server_exe.is_file():
            raise RuntimeError(f"missing bundled server binary: {server_exe}")
        if not worker_exe.is_file():
            raise RuntimeError(f"missing bundled worker binary: {worker_exe}")
        server_exe.chmod(server_exe.stat().st_mode | 0o755)
        worker_exe.chmod(worker_exe.stat().st_mode | 0o755)
        run_stdio_smoke(server_exe, extracted_root, fixture_root, want_version)
        run_fmt_path_resolution_smoke(server_exe, extracted_root, want_version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
