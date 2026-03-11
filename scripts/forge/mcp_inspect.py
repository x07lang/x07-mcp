#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from common import canonical_json_text, parse_json_arg, write_json


_SECRET_HEADERS = {"authorization", "cookie", "set-cookie"}
_DEFAULT_PROTOCOL_VERSION = "2025-11-25"


class InspectError(RuntimeError):
    pass


def _redact_headers(headers: dict[str, str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in headers.items():
        out[key] = "<redacted>" if key.lower() in _SECRET_HEADERS else value
    return out


def _ensure_object(value: Any, *, what: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise InspectError(f"{what} must decode to a JSON object")
    return value


def _parse_json_body(body_text: str) -> Any | None:
    if not body_text.strip():
        return None
    try:
        return json.loads(body_text)
    except json.JSONDecodeError:
        return None


def _parse_sse_body(body_text: str) -> dict[str, Any]:
    events: list[dict[str, str]] = []
    current: dict[str, list[str]] = {"data": []}
    for raw_line in body_text.splitlines():
        line = raw_line.rstrip("\r")
        if not line:
            event = {
                "event": "".join(current.get("event", [])),
                "id": "".join(current.get("id", [])),
                "data": "\n".join(current.get("data", [])),
            }
            if event["event"] or event["id"] or event["data"]:
                events.append(event)
            current = {"data": []}
            continue
        if line.startswith(":"):
            continue
        field, _, value = line.partition(":")
        if value.startswith(" "):
            value = value[1:]
        current.setdefault(field, []).append(value)
    if current.get("event") or current.get("id") or current.get("data"):
        events.append(
            {
                "event": "".join(current.get("event", [])),
                "id": "".join(current.get("id", [])),
                "data": "\n".join(current.get("data", [])),
            }
        )
    parsed_json = None
    for event in reversed(events):
        parsed_json = _parse_json_body(event["data"])
        if parsed_json is not None:
            break
    return {"mode": "sse", "events": events, "json": parsed_json, "text": body_text}


def _decode_response_body(headers: dict[str, str], body: bytes) -> dict[str, Any]:
    text = body.decode("utf-8", errors="replace")
    content_type = headers.get("content-type", "")
    if "text/event-stream" in content_type or "\ndata:" in text or text.startswith("event:"):
        return _parse_sse_body(text)
    parsed_json = _parse_json_body(text)
    mode = "json" if parsed_json is not None else "text"
    return {"mode": mode, "json": parsed_json, "text": text}


class HttpMcpClient:
    def __init__(
        self,
        *,
        url: str,
        headers: dict[str, str],
        protocol_version: str,
        timeout_ms: int,
    ) -> None:
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or not parsed.path:
            raise InspectError(f"invalid --url: {url!r}")
        self._parsed = parsed
        self._url = url
        self._headers = headers
        self._protocol_version = protocol_version
        self._timeout = max(timeout_ms / 1000.0, 1.0)
        self._session_id = ""
        self._next_id = 1

    @property
    def transport_meta(self) -> dict[str, Any]:
        return {
            "kind": "http",
            "url": self._url,
            "protocol_version": self._protocol_version,
            "session_id": self._session_id,
            "headers": _redact_headers(self._headers),
        }

    def _request(self, payload: dict[str, Any], *, expect_body: bool) -> dict[str, Any]:
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": self._protocol_version,
            **self._headers,
        }
        if self._session_id:
            headers["MCP-Session-Id"] = self._session_id

        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        port = self._parsed.port or (443 if self._parsed.scheme == "https" else 80)
        conn_cls = http.client.HTTPSConnection if self._parsed.scheme == "https" else http.client.HTTPConnection
        conn = conn_cls(self._parsed.hostname, port, timeout=self._timeout)
        try:
            conn.request("POST", self._parsed.path, body=body, headers=headers)
            resp = conn.getresponse()
            resp_body = resp.read()
            response_headers = {key.lower(): value for key, value in resp.getheaders()}
            if not self._session_id:
                self._session_id = response_headers.get("mcp-session-id", "")
            parsed_body = _decode_response_body(response_headers, resp_body)
            if expect_body and resp.status >= 400:
                raise InspectError(f"http request failed with status {resp.status}")
            return {
                "request": {"headers": _redact_headers(headers), "json": payload},
                "response": {
                    "status": resp.status,
                    "headers": _redact_headers(response_headers),
                    "body": parsed_body,
                },
            }
        finally:
            conn.close()

    def initialize(self) -> dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": self._next_id,
            "method": "initialize",
            "params": {"protocolVersion": self._protocol_version, "capabilities": {}},
        }
        self._next_id += 1
        init = self._request(payload, expect_body=True)
        init_body = init["response"]["body"].get("json")
        if not isinstance(init_body, dict) or "result" not in init_body:
            raise InspectError("initialize did not return a JSON-RPC result")

        notif = {
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {},
        }
        notif_result = self._request(notif, expect_body=False)
        return {"initialize": init, "initialized_notification": notif_result}

    def call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        payload = {"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params}
        self._next_id += 1
        return self._request(payload, expect_body=True)


class StdioMcpClient:
    def __init__(
        self,
        *,
        command: str,
        argv: list[str],
        cwd: str,
        protocol_version: str,
        timeout_ms: int,
    ) -> None:
        if not command:
            raise InspectError("stdio transport requires --command")
        self._cmd = [command, *argv]
        self._cwd = cwd
        self._protocol_version = protocol_version
        self._timeout = max(timeout_ms / 1000.0, 1.0)
        self._next_id = 1
        self._proc = subprocess.Popen(
            self._cmd,
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    @property
    def transport_meta(self) -> dict[str, Any]:
        return {
            "kind": "stdio",
            "command": self._cmd[0],
            "argv": self._cmd[1:],
            "cwd": self._cwd,
            "protocol_version": self._protocol_version,
        }

    def close(self) -> None:
        if self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                self._proc.wait(timeout=2.0)

    def _read_response(self, response_id: int) -> dict[str, Any]:
        assert self._proc.stdout is not None
        deadline = time.time() + self._timeout
        while True:
            if time.time() >= deadline:
                raise InspectError(f"timeout waiting for stdio response id={response_id}")
            line = self._proc.stdout.readline()
            if line == "":
                stderr_text = ""
                if self._proc.stderr is not None:
                    stderr_text = self._proc.stderr.read().strip()
                raise InspectError(f"stdio server exited while waiting for response: {stderr_text}")
            payload = _parse_json_body(line)
            if isinstance(payload, dict) and payload.get("id") == response_id:
                return payload

    def _write_json_line(self, payload: dict[str, Any]) -> None:
        assert self._proc.stdin is not None
        self._proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self._proc.stdin.flush()

    def initialize(self) -> dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": self._next_id,
            "method": "initialize",
            "params": {"protocolVersion": self._protocol_version, "capabilities": {}},
        }
        self._next_id += 1
        self._write_json_line(payload)
        init_body = self._read_response(payload["id"])
        if "result" not in init_body:
            raise InspectError("initialize did not return a JSON-RPC result")
        notif = {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}
        self._write_json_line(notif)
        return {
            "initialize": {
                "request": {"json": payload},
                "response": {"status": 200, "headers": {}, "body": {"mode": "json", "json": init_body, "text": json.dumps(init_body, separators=(",", ":"))}},
            },
            "initialized_notification": {
                "request": {"json": notif},
                "response": {"status": 202, "headers": {}, "body": {"mode": "json", "json": None, "text": ""}},
            },
        }

    def call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        payload = {"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params}
        self._next_id += 1
        self._write_json_line(payload)
        response = self._read_response(payload["id"])
        return {
            "request": {"json": payload},
            "response": {
                "status": 200,
                "headers": {},
                "body": {"mode": "json", "json": response, "text": json.dumps(response, separators=(",", ":"))},
            },
        }


def _build_operation(subcmd: str, args: argparse.Namespace) -> tuple[str | None, dict[str, Any]]:
    if subcmd == "initialize":
        return (None, {})
    if subcmd == "tools":
        params = {"cursor": args.cursor} if args.cursor else {}
        return ("tools/list", params)
    if subcmd == "tool-call":
        if not args.name:
            raise InspectError("tool-call requires --name")
        params: dict[str, Any] = {
            "name": args.name,
            "arguments": _ensure_object(parse_json_arg(args.args_json, default={}, what="--args-json"), what="--args-json"),
        }
        if args.task_json:
            params["task"] = _ensure_object(parse_json_arg(args.task_json, default={}, what="--task-json"), what="--task-json")
        return ("tools/call", params)
    if subcmd == "prompts":
        params = {"cursor": args.cursor} if args.cursor else {}
        return ("prompts/list", params)
    if subcmd == "prompt-get":
        if not args.name:
            raise InspectError("prompt-get requires --name")
        return (
            "prompts/get",
            {
                "name": args.name,
                "arguments": _ensure_object(parse_json_arg(args.args_json, default={}, what="--args-json"), what="--args-json"),
            },
        )
    if subcmd == "resources":
        params = {"cursor": args.cursor} if args.cursor else {}
        return ("resources/list", params)
    if subcmd == "resource-read":
        if not args.resource_uri:
            raise InspectError("resource-read requires --resource-uri")
        return ("resources/read", {"uri": args.resource_uri})
    if subcmd == "tasks":
        params = {"cursor": args.cursor} if args.cursor else {}
        return ("tasks/list", params)
    if subcmd == "task-poll":
        if not args.task_id:
            raise InspectError("task-poll requires --task-id")
        return ("tasks/get", {"taskId": args.task_id})
    raise InspectError(f"unsupported inspect subcommand: {subcmd}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect MCP servers over HTTP or stdio")
    parser.add_argument("subcmd", choices=["initialize", "tools", "tool-call", "prompts", "prompt-get", "resources", "resource-read", "tasks", "task-poll"])
    parser.add_argument("--transport", choices=["auto", "http", "stdio"], default="auto")
    parser.add_argument("--url", default="")
    parser.add_argument("--command", default="")
    parser.add_argument("--argv-json", default="[]")
    parser.add_argument("--cwd", default=".")
    parser.add_argument("--headers-json", default="{}")
    parser.add_argument("--protocol-version", default=_DEFAULT_PROTOCOL_VERSION)
    parser.add_argument("--timeout-ms", type=int, default=30000)
    parser.add_argument("--name", default="")
    parser.add_argument("--args-json", default="{}")
    parser.add_argument("--task-json", default="")
    parser.add_argument("--resource-uri", default="")
    parser.add_argument("--task-id", default="")
    parser.add_argument("--cursor", default="")
    parser.add_argument("--out", default="")
    parser.add_argument("--machine", choices=["json"], default=None)
    args = parser.parse_args()

    out_path = Path(args.out) if args.out else Path(".x07/artifacts/mcp/inspect") / f"{args.subcmd}.json"
    try:
        headers = parse_json_arg(args.headers_json, default={}, what="--headers-json")
        headers_obj = {str(k): str(v) for k, v in _ensure_object(headers, what="--headers-json").items()}
        transport = args.transport
        if transport == "auto":
            transport = "http" if args.url else "stdio"
        operation, params = _build_operation(args.subcmd, args)

        if transport == "http":
            if not args.url:
                raise InspectError("http transport requires --url")
            client: HttpMcpClient | StdioMcpClient = HttpMcpClient(
                url=args.url,
                headers=headers_obj,
                protocol_version=args.protocol_version,
                timeout_ms=args.timeout_ms,
            )
        else:
            argv = parse_json_arg(args.argv_json, default=[], what="--argv-json")
            if not isinstance(argv, list) or not all(isinstance(item, str) for item in argv):
                raise InspectError("--argv-json must decode to a JSON array of strings")
            client = StdioMcpClient(
                command=args.command,
                argv=argv,
                cwd=args.cwd,
                protocol_version=args.protocol_version,
                timeout_ms=args.timeout_ms,
            )

        try:
            init_info = client.initialize()
            doc: dict[str, Any] = {
                "schema_version": "x07.mcp.inspect.result@0.1.0",
                "ok": True,
                "operation": args.subcmd,
                "transport": client.transport_meta,
                "initialize": init_info,
            }
            if operation is not None:
                call_info = client.call(operation, params)
                doc["rpc"] = {"method": operation, **call_info}
            doc["artifact_path"] = str(out_path.resolve())
            write_json(out_path, doc)
        finally:
            if isinstance(client, StdioMcpClient):
                client.close()
    except Exception as exc:
        doc = {
            "schema_version": "x07.mcp.inspect.result@0.1.0",
            "ok": False,
            "operation": args.subcmd,
            "error": str(exc),
        }
        doc["artifact_path"] = str(out_path.resolve())
        write_json(out_path, doc)
        sys.stdout.write(canonical_json_text(doc) if args.machine == "json" else json.dumps(doc, indent=2, sort_keys=True) + "\n")
        return 1

    sys.stdout.write(canonical_json_text(doc) if args.machine == "json" else json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
