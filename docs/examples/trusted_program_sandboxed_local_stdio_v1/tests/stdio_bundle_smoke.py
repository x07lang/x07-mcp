#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def example_root() -> Path:
    return Path(__file__).resolve().parents[1]


def x07_exe() -> str:
    env_exe = os.environ.get("X07_EXE")
    if env_exe:
        return env_exe
    found = shutil.which("x07")
    if found:
        return found
    raise RuntimeError("missing x07 executable in PATH; set X07_EXE or add x07 to PATH")


def expected_server_version(root: Path) -> str:
    cfg = json.loads((root / "config" / "mcp.server.json").read_text(encoding="utf-8"))
    server = cfg.get("server")
    if not isinstance(server, dict):
        raise RuntimeError("config/mcp.server.json missing server object")
    version = server.get("version")
    if not isinstance(version, str) or not version:
        raise RuntimeError("config/mcp.server.json missing server.version")
    return version


def build_bundles(root: Path) -> None:
    x07 = x07_exe()
    subprocess.run(
        [x07, "bundle", "--project", "x07.json", "--profile", "sandbox_router", "--out", "out/mcp-router"],
        cwd=root,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        [
            x07,
            "bundle",
            "--project",
            "x07.json",
            "--profile",
            "sandbox_worker",
            "--program",
            "src/worker_main.x07.json",
            "--out",
            "out/mcp-worker",
        ],
        cwd=root,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> int:
    root = example_root()
    repo = repo_root()
    sys.path.insert(0, str(repo / "servers" / "x07lang-mcp" / "tests"))
    from stdio_smoke_lib import run_stdio_smoke_cmd

    build_bundles(root)
    router_bin = root / "out" / "mcp-router"
    if not router_bin.is_file():
        raise RuntimeError(f"missing router bundle: {router_bin}")
    worker_bin = root / "out" / "mcp-worker"
    if not worker_bin.is_file():
        raise RuntimeError(f"missing worker bundle: {worker_bin}")

    run_stdio_smoke_cmd(
        [str(router_bin)],
        root,
        expected_server_version(root),
        "echo",
        {"text": "hello from stdio bundle smoke"},
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
