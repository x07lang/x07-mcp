# Build `.mcpb` bundles

`x07-mcp` can build deterministic `.mcpb` artifacts for reference-style server layouts.

## Build from a server directory

```sh
x07-mcp bundle --mcpb --server-dir servers/postgres-mcp
```

Optional explicit output path:

```sh
x07-mcp bundle \
  --mcpb \
  --server-dir servers/postgres-mcp \
  --out servers/postgres-mcp/dist/postgres-mcp.mcpb
```

The command runs the server’s `publish/build_mcpb.sh` recipe and writes the bundle into `dist/`.

For publish-ready servers, the recipe should rebuild fresh router/worker binaries before packing and refresh `dist/server.json` from `x07.mcp.json` so bundle metadata stays in sync with the packaged artifact.
