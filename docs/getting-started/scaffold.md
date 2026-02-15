# Scaffold a server

Use either `x07` (delegation) or `x07-mcp` directly.

## Stdio template

```sh
x07 init --template mcp-server-stdio --dir ./my-mcp-server
```

Or:

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-mcp-server
```

Install dependencies:

```sh
cd ./my-mcp-server
x07 pkg add ext-mcp-transport-stdio@0.1.1 --sync
x07 pkg add ext-mcp-rr@0.1.1 --sync
x07 pkg add ext-hex-rs@0.1.4 --sync
```

The template is organized around:

- a **router** program (stdio transport + JSON-RPC/MCP dispatch)
- a **worker** program (one tool call per process under `run-os-sandboxed`)
- config files:
  - `config/mcp.server.json` (`x07.mcp.server_config@0.1.0`)
  - `config/mcp.tools.json` (`x07.mcp.tools_manifest@0.1.0`)
