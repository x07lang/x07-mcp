# Install

## Prerequisites

- The X07 toolchain (`x07`) available on your `PATH`.
- A Rust toolchain to build `x07-mcp` locally.

## Build and install (local dev)

From the `x07-mcp/` repo:

```sh
cargo install --path crates/x07-mcp-cli
```

Verify:

```sh
x07-mcp --help
```

## Delegation from `x07`

If `x07-mcp` is on your `PATH`:

- `x07 mcp ...` delegates to `x07-mcp ...`
- `x07 init --template mcp-server-stdio ...` delegates to `x07-mcp scaffold init ...`
