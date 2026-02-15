# MCP Server (HTTP) — Template

This template scaffolds a minimal MCP **HTTP** server in X07 with a router/worker split:

- **Router**: HTTP transport + lifecycle + JSON-RPC dispatch
- **Worker**: one `tools/call` execution under `run-os-sandboxed`

## Layout

- `config/mcp.server.json`: server config (`x07.mcp.server_config@0.2.0`)
- `config/mcp.tools.json`: tools manifest (`x07.mcp.tools_manifest@0.2.0`)
- `config/mcp.oauth.json`: OAuth test-static config (`x07.mcp.oauth@0.1.0`)
- `src/main.x07.json`: router entry
- `src/worker_main.x07.json`: worker entry
- `src/mcp/user.x07.json`: tool implementations
- `tests/`: smoke, compile-import, and HTTP replay fixtures

## Quickstart

Add dependencies:

```sh
x07 pkg add ext-mcp-transport-http@0.1.0 --sync
x07 pkg add ext-mcp-rr@0.2.0 --sync
```

Bundle router + worker:

```sh
x07 bundle --profile os --out out/mcp-router
x07 bundle --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
```

Run the router (HTTP endpoint):

```sh
./out/mcp-router
```

The MCP endpoint is `http://127.0.0.1:8314/mcp` in the default config.

Run tests:

```sh
x07 test --manifest tests/tests.json
```
