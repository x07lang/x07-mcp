#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import selectors
import subprocess
import sys
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
        raise RuntimeError("server stdout closed")
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


def _build_bins(server_root: Path) -> None:
    env = os.environ.copy()
    env["X07_MCP_BUILD_BINS_ONLY"] = "1"
    subprocess.run(
        [str(server_root / "publish" / "build_mcpb.sh")],
        cwd=server_root,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> int:
    server_root = Path(__file__).resolve().parents[1]
    _build_bins(server_root)

    router_bin = server_root / "out" / "x07lang-mcp"
    if not router_bin.is_file():
        raise RuntimeError(f"missing router binary: {router_bin}")

    proc = subprocess.Popen(
        [str(router_bin)],
        cwd=server_root,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
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
                        "repo_root": "tests/fixtures/search_ws",
                        "limit": 1,
                    },
                },
            },
        )
        _wait_for_response_id(proc, 2, 20.0)
        return 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)


if __name__ == "__main__":
    sys.exit(main())
