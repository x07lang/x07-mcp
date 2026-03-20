#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import selectors
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


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


def _spawn_stdio_proc(
    command: list[str],
    cwd: Path,
    extra_env: dict[str, str] | None = None,
) -> subprocess.Popen[str]:
    env = stdio_env(cwd)
    if extra_env:
        env.update(extra_env)
    return subprocess.Popen(
        command,
        cwd=cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=env,
    )


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


def _assert_initialize_protocol(resp: dict, requested_protocol: str) -> None:
    result = resp.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"initialize missing result payload: {resp!r}")
    negotiated = result.get("protocolVersion")
    if negotiated != requested_protocol:
        raise AssertionError(
            f"initialize protocol mismatch: requested={requested_protocol!r} got={negotiated!r}"
        )


def _assert_initialize_server_version(resp: dict, expected_version: str) -> None:
    result = resp.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"initialize missing result payload: {resp!r}")
    server_info = result.get("serverInfo")
    if not isinstance(server_info, dict):
        raise AssertionError(f"initialize missing serverInfo payload: {resp!r}")
    got = server_info.get("version")
    if got != expected_version:
        raise AssertionError(
            f"initialize server version mismatch: expected={expected_version!r} got={got!r}"
        )


def _assert_tool_call_success(resp: dict, tool_name: str) -> None:
    if "error" in resp:
        raise AssertionError(f"{tool_name} returned jsonrpc error: {resp!r}")
    result = resp.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"{tool_name} missing result payload: {resp!r}")
    if result.get("isError") is True:
        raise AssertionError(f"{tool_name} returned MCP tool error: {resp!r}")


def expected_server_version(server_root: Path) -> str:
    doc = json.loads((server_root / "x07.mcp.json").read_text(encoding="utf-8"))
    version = doc.get("version")
    if not isinstance(version, str) or not version:
        raise RuntimeError("x07.mcp.json missing version")
    return version


def _workspace_x07_candidates(server_root: Path) -> list[Path]:
    candidates: list[Path] = []
    if os.environ.get("X07_ROOT"):
        candidates.append(Path(os.environ["X07_ROOT"]).resolve())
    candidates.extend(
        [
            server_root.parents[2] / "x07",
            Path(__file__).resolve().parents[4] / "x07",
        ]
    )
    return candidates


def source_repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def workspace_x07_root(server_root: Path) -> Path | None:
    saw_candidate = False
    for candidate in _workspace_x07_candidates(server_root):
        if candidate.is_dir():
            saw_candidate = True
            break
    if not saw_candidate:
        return None

    repo_root = source_repo_root()
    resolver = repo_root / "scripts" / "ci" / "resolve_workspace_x07_root.sh"
    resolved = subprocess.run(
        [str(resolver)],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if resolved.returncode != 0:
        detail = resolved.stderr.strip() or resolved.stdout.strip() or "failed to resolve pinned x07 workspace"
        raise RuntimeError(detail)
    candidate = Path(resolved.stdout.strip())
    if candidate.is_dir():
        return candidate
    return None


def workspace_x07_exe(server_root: Path) -> Path | None:
    x07_root = workspace_x07_root(server_root)
    if x07_root is None:
        return None
    candidate = x07_root / "target" / "debug" / "x07"
    if candidate.is_file():
        return candidate
    return None


def resolved_x07_exe(server_root: Path) -> Path | None:
    env_override = os.environ.get("X07_MCP_X07_EXE", "")
    if env_override:
        candidate = Path(env_override)
        if candidate.is_file():
            return candidate

    workspace_x07 = workspace_x07_exe(server_root)
    if workspace_x07 is not None:
        return workspace_x07

    x07_exe = shutil.which("x07")
    if x07_exe:
        return Path(x07_exe)
    return None


def tool_env(server_root: Path) -> dict[str, str]:
    env = os.environ.copy()
    workspace_x07 = workspace_x07_root(server_root)
    x07_exe = resolved_x07_exe(server_root)
    if x07_exe is not None:
        env["X07_MCP_X07_EXE"] = str(x07_exe)
        env["PATH"] = f"{x07_exe.parent}{os.pathsep}{env.get('PATH', '')}"
    if workspace_x07 is not None:
        env.setdefault("X07_MCP_LOCAL_DEPS", "1")
        env.setdefault("X07_MCP_LOCAL_DEPS_REFRESH", "1")
    return env


def build_bins(server_root: Path) -> None:
    env = tool_env(server_root)
    env["X07_MCP_BUILD_BINS_ONLY"] = "1"
    hydrate_server_deps(server_root, env)
    subprocess.run(
        [str(server_root / "publish" / "build_mcpb.sh")],
        cwd=server_root,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def build_bundle(server_root: Path) -> Path:
    env = tool_env(server_root)
    hydrate_server_deps(server_root, env)
    subprocess.run(
        [str(server_root / "publish" / "build_mcpb.sh")],
        cwd=server_root,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    bundle_path = server_root / "dist" / "x07lang-mcp.mcpb"
    if not bundle_path.is_file():
        raise RuntimeError(f"missing bundle: {bundle_path}")
    return bundle_path


def stdio_env(cwd: Path) -> dict[str, str]:
    server_root = cwd if (cwd / "x07.mcp.json").is_file() else Path(__file__).resolve().parents[1]
    return tool_env(server_root)


def hydrate_server_deps(server_root: Path, env: dict[str, str]) -> None:
    repo_root = server_root.parents[1]
    install_script = repo_root / "servers" / "_shared" / "ci" / "install_server_deps.sh"
    subprocess.run(
        [str(install_script), str(server_root)],
        cwd=repo_root,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def run_stdio_smoke(
    server_exe: Path, cwd: Path, fixture_root: Path, expected_version: str
) -> None:
    run_stdio_smoke_cmd(
        [str(server_exe)],
        cwd,
        expected_version,
        "x07.search_v1",
        {
            "query": "hello",
            "domain": "docs",
            "repo_root": str(fixture_root),
            "limit": 1,
        },
    )


def _initialize_stdio_session(
    command: list[str],
    cwd: Path,
    expected_version: str,
    extra_env: dict[str, str] | None = None,
) -> subprocess.Popen[str]:
    proc = _spawn_stdio_proc(command, cwd, extra_env)
    try:
        for requested_protocol in ("2025-03-26", "2025-11-25"):
            _send_json_line(
                proc,
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": requested_protocol,
                        "capabilities": {},
                    },
                },
            )
            resp = _wait_for_response_id(proc, 1, 10.0)
            _assert_initialize_protocol(resp, requested_protocol)
            _assert_initialize_server_version(resp, expected_version)
            if requested_protocol == "2025-11-25":
                break

            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2.0)

            proc = _spawn_stdio_proc(command, cwd, extra_env)

        _send_json_line(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        return proc
    except Exception:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)
        raise


def _call_tool(
    proc: subprocess.Popen[str],
    request_id: int,
    tool_name: str,
    tool_arguments: dict[str, Any],
) -> dict[str, Any]:
    _send_json_line(
        proc,
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": tool_arguments,
            },
        },
    )
    resp = _wait_for_response_id(proc, request_id, 20.0)
    if not isinstance(resp, dict):
        raise AssertionError(f"{tool_name} returned non-object response: {resp!r}")
    _assert_tool_call_success(resp, tool_name)
    return resp


def _write_fake_cli(path: Path, name: str) -> None:
    if name == "x07-wasm":
        script = """#!/bin/sh
set -eu
printf '{"tool":"x07-wasm","argv":["'
sep=''
for arg in "$@"; do
  printf '%s%s' "$sep" "$arg"
  sep='","'
done
printf '"],"ok":true}\n'
"""
    else:
        script = """#!/bin/sh
set -eu
printf '{"tool":"x07lp","argv":["'
sep=''
for arg in "$@"; do
  printf '%s%s' "$sep" "$arg"
  sep='","'
done
printf '"],"ok":true}\n'
"""
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def _write_broken_x07(path: Path, marker: Path) -> None:
    script = f"""#!/bin/sh
set -eu
touch '{marker}'
exit 17
"""
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def run_paas_surface_smoke(server_exe: Path, server_root: Path, expected_version: str) -> None:
    fixtures_root = server_root / "tests" / "fixtures"
    with tempfile.TemporaryDirectory(
        dir=fixtures_root,
        prefix="paas-surface-smoke-",
    ) as temp_dir:
        temp_root = Path(temp_dir)
        service_dir = temp_root / "service-app"
        service_dir.mkdir()
        shim_bin_dir = temp_root / "shim-bin"
        shim_bin_dir.mkdir()
        shim_paths: dict[str, Path] = {}
        for tool_name in ("x07-wasm", "x07lp"):
            tool_path = shim_bin_dir / tool_name
            _write_fake_cli(tool_path, tool_name)
            shim_paths[tool_name] = tool_path

        proc = _initialize_stdio_session(
            [str(server_exe)],
            server_root,
            expected_version,
            extra_env={
                "X07_MCP_X07_WASM_EXE": str(shim_paths["x07-wasm"]),
                "X07_MCP_X07LP_EXE": str(shim_paths["x07lp"]),
            },
        )
        try:
            _call_tool(
                proc,
                2,
                "x07.service.archetypes_v1",
                {"cwd": str(temp_root)},
            )
            _call_tool(
                proc,
                3,
                "x07.service.genpack.schema_v1",
                {"archetype": "api-cell", "cwd": str(temp_root)},
            )
            _call_tool(
                proc,
                4,
                "x07.service.genpack.grammar_v1",
                {"archetype": "api-cell", "cwd": str(temp_root)},
            )
            _call_tool(
                proc,
                5,
                "x07.service.init_v1",
                {"template": "api-cell", "cwd": str(service_dir)},
            )
            _call_tool(
                proc,
                6,
                "x07.service.validate_v1",
                {"cwd": str(service_dir)},
            )
            _call_tool(
                proc,
                7,
                "x07.workload.inspect_v1",
                {"cwd": str(service_dir)},
            )
            _call_tool(
                proc,
                8,
                "x07.topology.preview_v1",
                {"cwd": str(service_dir)},
            )
            _call_tool(
                proc,
                9,
                "lp.release.submit_v1",
                {
                    "workload_id": "orders-api",
                    "pack_digest": "sha256:abc123",
                },
            )
            _call_tool(
                proc,
                10,
                "lp.release.query_v1",
                {"release_id": "rel-123", "view": "evidence"},
            )
            _call_tool(
                proc,
                11,
                "lp.release.explain_v1",
                {"release_id": "rel-123"},
            )
            _call_tool(
                proc,
                12,
                "lp.release.rollback_v1",
                {"release_id": "rel-123", "reason": "smoke"},
            )
            _call_tool(
                proc,
                13,
                "lp.binding.status_v1",
                {"binding_id": "orders-db"},
            )
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2.0)


def run_fmt_path_resolution_smoke(
    server_exe: Path,
    server_root: Path,
    expected_version: str,
    good_x07: Path | None = None,
) -> None:
    fixtures_root = server_root / "tests" / "fixtures"
    temp_parent = fixtures_root if fixtures_root.is_dir() else server_root
    with tempfile.TemporaryDirectory(
        dir=temp_parent,
        prefix="fmt-path-smoke-",
    ) as temp_dir:
        temp_root = Path(temp_dir)
        if good_x07 is None:
            good_x07 = resolved_x07_exe(server_root)
        if good_x07 is None:
            raise RuntimeError("missing real x07 executable for PATH smoke")
        home_dir = temp_root / "home"
        broken_bin_dir = home_dir / ".x07" / "bin"
        broken_bin_dir.mkdir(parents=True)
        broken_marker = temp_root / "broken-home-hit.txt"
        _write_broken_x07(broken_bin_dir / "x07", broken_marker)

        target_file = temp_root / "sample.x07.json"
        target_file.write_text(
            '{"module_id":"demo","imports":[],"decls":[],"kind":"module","schema_version":"x07.x07ast@0.8.0"}',
            encoding="utf-8",
        )

        path_env = f"{good_x07.parent}{os.pathsep}{os.environ.get('PATH', '')}"
        proc = _initialize_stdio_session(
            [str(server_exe)],
            server_root,
            expected_version,
            extra_env={
                "HOME": str(home_dir),
                "PATH": path_env,
                "X07_MCP_X07_EXE": "",
            },
        )
        try:
            _call_tool(
                proc,
                2,
                "x07.fmt_write_v1",
                {"path": str(target_file)},
            )
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2.0)

        if broken_marker.exists():
            raise AssertionError("formatter resolution used the broken HOME shim")
        formatted = target_file.read_text(encoding="utf-8")
        if not formatted.endswith("\n"):
            raise AssertionError("formatter output is missing the trailing newline")
        if '"schema_version":"x07.x07ast@0.8.0"' not in formatted:
            raise AssertionError(f"unexpected formatter output: {formatted!r}")


def run_stdio_smoke_cmd(
    command: list[str],
    cwd: Path,
    expected_version: str,
    tool_name: str,
    tool_arguments: dict[str, Any],
    extra_env: dict[str, str] | None = None,
) -> None:
    proc = _initialize_stdio_session(command, cwd, expected_version, extra_env)
    try:
        _call_tool(proc, 2, tool_name, tool_arguments)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)
