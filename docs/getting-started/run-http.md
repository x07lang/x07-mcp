# Run an HTTP server

The HTTP router entrypoint is `std.mcp.transport.http.serve_from_fs_v1`.

## 1) Bundle router + worker

From your project directory:

```sh
x07 bundle --profile os --out out/mcp-router
x07 bundle --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
```

`config/mcp.server.json` defaults `worker_exe_path` to `out/mcp-worker`.

## 2) Run the router

```sh
./out/mcp-router
```

Default endpoint values from the template:

- bind: `127.0.0.1:8314`
- MCP path: `/mcp`
- PRM path: `/.well-known/oauth-protected-resource`
- SSE enabled: `transport.sse_enabled=true`

## 3) Run deterministic replay tests

```sh
x07 test --manifest tests/tests.json
```

HTTP replay fixtures live under `tests/.x07_rr/sessions/`.

## 4) Probe POST SSE and GET listen SSE

Initialize first and keep the returned `MCP-Session-Id`:

```sh
curl -i \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json,text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}' \
  http://127.0.0.1:8314/mcp
```

Open a listen stream:

```sh
curl -N \
  -H 'Accept: text/event-stream' \
  -H "MCP-Session-Id: <session-id>" \
  http://127.0.0.1:8314/mcp
```
