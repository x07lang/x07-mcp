#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import selectors
import shutil
import subprocess
import time
from pathlib import Path


def _send_json_line(proc: subprocess.Popen[str], msg: object) -> None:
    line = json.dumps(msg, separators=(",", ":"))
    assert proc.stdin is not None
    proc.stdin.write(line + "\n")
    proc.stdin.flush()


def _read_next_json_line(proc: subprocess.Popen[str], timeout_secs: float) -> object:
    assert proc.stdout is not None

    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    ready = sel.select(timeout_secs)
    if not ready:
        raise TimeoutError("timeout waiting for server stdout")

    line = proc.stdout.readline()
    if line == "":
        stderr_text = ""
        if proc.stderr is not None:
            stderr_text = proc.stderr.read()
        raise RuntimeError(f"server stdout closed: {stderr_text.strip()}")
    return json.loads(line)


def _wait_for_response_id(
    proc: subprocess.Popen[str], response_id: int, timeout_secs: float
) -> dict:
    deadline = time.time() + timeout_secs
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            raise TimeoutError(f"timeout waiting for response id={response_id}")
        msg = _read_next_json_line(proc, remaining)
        if isinstance(msg, dict) and msg.get("id") == response_id:
            return msg


def build_bins(server_root: Path) -> None:
    env = os.environ.copy()
    env["X07_MCP_BUILD_BINS_ONLY"] = "1"
    subprocess.run(
        [str(server_root / "publish" / "build_mcpb.sh")],
        cwd=server_root,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def build_bundle(server_root: Path) -> Path:
    subprocess.run(
        [str(server_root / "publish" / "build_mcpb.sh")],
        cwd=server_root,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    bundle_path = server_root / "dist" / "x07lang-mcp.mcpb"
    if not bundle_path.is_file():
        raise RuntimeError(f"missing bundle: {bundle_path}")
    return bundle_path


def stdio_env() -> dict[str, str]:
    env = os.environ.copy()
    x07_exe = shutil.which("x07")
    if x07_exe:
        env["X07_MCP_X07_EXE"] = x07_exe
    return env


def run_stdio_smoke(server_exe: Path, cwd: Path, fixture_root: Path) -> None:
    proc = subprocess.Popen(
        [str(server_exe)],
        cwd=cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=stdio_env(),
    )
    try:
        _send_json_line(
            proc,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-11-25", "capabilities": {}},
            },
        )
        _wait_for_response_id(proc, 1, 10.0)

        _send_json_line(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        _send_json_line(
            proc,
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {
                    "name": "x07.search_v1",
                    "arguments": {
                        "query": "hello",
                        "domain": "docs",
                        "repo_root": str(fixture_root),
                        "limit": 1,
                    },
                },
            },
        )
        _wait_for_response_id(proc, 2, 20.0)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)
