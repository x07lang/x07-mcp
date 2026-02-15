# Install

## Prerequisites

- The X07 toolchain (`x07`) available on your `PATH`.
- A C toolchain supported by `x07 bundle` (clang/gcc).

## Build and install (local dev)

From the `x07-mcp/` repo:

```sh
x07 bundle --project x07.json --profile os --out dist/x07-mcp
```

Verify:

```sh
./dist/x07-mcp --help
```

Put `dist/x07-mcp` on your `PATH` to enable `x07` delegation.

## Delegation from `x07`

If `x07-mcp` is on your `PATH`:

- `x07 mcp ...` delegates to `x07-mcp ...`
- `x07 init --template mcp-server-stdio ...` delegates to `x07-mcp scaffold init ...`
