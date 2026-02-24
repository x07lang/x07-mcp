#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _read_bytes(path: Path) -> bytes:
    return path.read_bytes()


def _must_str(d: dict[str, Any], key: str) -> str:
    v = d.get(key)
    if not isinstance(v, str) or not v:
        raise ValueError(f"missing/invalid {key}")
    return v


class _ScenarioServer:
    def __init__(self, prm_body: bytes, www_auth_value: str) -> None:
        self._prm_body = prm_body
        self._www_auth_value = www_auth_value
        self.requests: list[str] = []
        self._srv: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self, host: str, port: int) -> None:
        scenario = self

        class Handler(BaseHTTPRequestHandler):
            def _record(self) -> None:
                scenario.requests.append(f"{self.command} {self.path}")

            def log_message(self, *_args: object) -> None:
                return

            def do_POST(self) -> None:  # noqa: N802
                self._record()
                if self.path != "/mcp":
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(401)
                self.send_header("WWW-Authenticate", scenario._www_auth_value)
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Type", "application/json")
                body = b'{"error":"unauthorized"}\n'
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:  # noqa: N802
                self._record()
                if self.path == "/.well-known/oauth-protected-resource":
                    body = scenario._prm_body
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                self.send_response(404)
                self.end_headers()

        self._srv = ThreadingHTTPServer((host, port), Handler)
        self._thread = threading.Thread(target=self._srv.serve_forever, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if not self._srv:
            return
        self._srv.shutdown()
        self._srv.server_close()
        self._srv = None
        if self._thread:
            self._thread.join(timeout=2)
            self._thread = None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", required=True)
    ap.add_argument("--client", default="dist/x07-mcp-conformance-client")
    ap.add_argument("--scenarios-root", default="conformance/client-auth/scenarios")
    args = ap.parse_args(argv)

    repo_root = Path.cwd()
    scenario_dir = (repo_root / args.scenarios_root / args.scenario).resolve()
    expected_path = scenario_dir / "expected/result.json"
    prm_path = scenario_dir / "server/prm.well-known.unsigned.json"
    www_auth_path = scenario_dir / "server/www-authenticate.challenge.txt"
    verify_cfg_path = scenario_dir / "client/verify_cfg.fail_closed.json"

    expected = json.loads(_read_text(expected_path))
    prm_obj = json.loads(_read_text(prm_path))

    server_url = _must_str(prm_obj, "resource")
    parsed = urlparse(server_url)
    if parsed.scheme != "http":
        raise ValueError(f"scenario server_url must be http: {server_url}")
    if parsed.hostname not in ("127.0.0.1", "localhost"):
        raise ValueError(f"scenario server_url must be localhost: {server_url}")
    if not parsed.port:
        raise ValueError(f"scenario server_url must include port: {server_url}")

    www_auth_value = _read_text(www_auth_path).strip()
    prm_body = _read_bytes(prm_path)

    srv = _ScenarioServer(prm_body=prm_body, www_auth_value=www_auth_value)
    srv.start(parsed.hostname, parsed.port)
    try:
        client_path = (repo_root / args.client).resolve()
        if not client_path.exists():
            raise FileNotFoundError(f"missing client binary: {client_path}")

        ctx = {
            "prm_verify_cfg_path": str(verify_cfg_path),
        }

        env = dict(os.environ)
        env["MCP_CONFORMANCE_SCENARIO"] = args.scenario
        env["MCP_CONFORMANCE_CONTEXT"] = json.dumps(ctx, separators=(",", ":"))

        expected_err = expected.get("expected_error_code")
        if not isinstance(expected_err, str) or not expected_err:
            raise ValueError("expected.result.json missing expected_error_code")

        expected_exit_code = {
            "PRM_SIGNED_METADATA_REQUIRED": 3,
        }.get(expected_err)
        if expected_exit_code is None:
            raise ValueError(f"no exit-code mapping for expected_error_code={expected_err!r}")

        proc = subprocess.run([str(client_path), server_url], env=env, check=False)
        if proc.returncode != expected_exit_code:
            raise RuntimeError(
                f"client exited {proc.returncode}, expected {expected_exit_code} (error={expected_err})"
            )

        expected_reqs = expected.get("expected_http_requests")
        if not isinstance(expected_reqs, list) or not all(isinstance(x, str) for x in expected_reqs):
            raise ValueError("expected.result.json missing/invalid expected_http_requests")
        if srv.requests != expected_reqs:
            raise RuntimeError(f"unexpected http requests: got={srv.requests!r} want={expected_reqs!r}")

        if expected.get("expected_auth_flow_started") is False:
            forbidden = (
                "GET /.well-known/oauth-authorization-server",
                "GET /.well-known/openid-configuration",
            )
            for req in srv.requests:
                if any(req.startswith(pfx) for pfx in forbidden):
                    raise RuntimeError(f"auth flow started unexpectedly: {req}")

        if expected.get("ok") is not True:
            raise ValueError("expected.result.json ok!=true (scenario definition error)")

        return 0
    finally:
        srv.stop()


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)
