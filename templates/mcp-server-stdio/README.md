# MCP Server (stdio) — Template

This template scaffolds a minimal MCP **stdio** server in X07 with a router/worker split:

- **Router**: stdio transport + lifecycle + JSON-RPC dispatch
- **Worker**: one `tools/call` execution under `run-os-sandboxed`

## Layout

- `config/mcp.server.json`: server config (`x07.mcp.server_config@0.3.0`)
- `config/mcp.tools.json`: tools manifest (`x07.mcp.tools_manifest@0.2.0`)
- `src/main.x07.json`: router entry
- `src/worker_main.x07.json`: worker entry
- `src/mcp/user.x07.json`: tool implementations
- `tests/`: smoke test plus replay fixture inputs/outputs

For the same layout upgraded onto the current sandboxed trust/capsule surface,
see `docs/examples/trusted_program_sandboxed_local_stdio_v1/`.

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

Run the router:

```sh
./out/mcp-router
```

Run tests:

```sh
x07 test --manifest tests/tests.json
```
