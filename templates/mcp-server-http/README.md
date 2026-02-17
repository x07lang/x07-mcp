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
- `src/mcp/user.x07.json`: dispatch shim for user tools
- `src/tools/hello.x07.json`: demo tools (`hello.echo`, `hello.work`, `hello.bump_resource`)
- `tests/`: smoke, compile-import, and HTTP replay fixtures

## Included Phase-4 demos

- `hello.echo`: simple typed echo tool.
- `hello.work`: emits `notifications/progress` and checks cancellation.
- `hello.bump_resource`: emits `notifications/resources/updated` for `hello://greeting`.
- `config/mcp.resources.json` includes `hello://greeting` for subscribe/read demos.

## Quickstart

Dependencies are already declared in `x07.json`. If you need to refresh lock/deps:

```sh
x07 pkg lock --project x07.json
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
