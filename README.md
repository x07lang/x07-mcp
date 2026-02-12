# x07-mcp

`x07-mcp` is the MCP kit companion tool for the X07 toolchain.

In Phase 0 it provides only **project scaffolding**, and is invoked by `x07` via delegation:

- `x07 mcp ...` delegates to `x07-mcp ...`
- `x07 init --template mcp-server|mcp-server-stdio|mcp-server-http` delegates to `x07-mcp scaffold init ...`

## Install (local dev)

Build and put `x07-mcp` on your `PATH`:

```sh
cargo install --path crates/x07-mcp-cli
```

## Scaffolding

Generate a new project skeleton:

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-mcp-server
```

Machine-readable output:

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-mcp-server --machine json
```
