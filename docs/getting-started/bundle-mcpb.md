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

## Machine-readable bundle summary

Use `--machine json` when a UI or agent needs structured readiness data:

```sh
x07-mcp bundle \
  --mcpb \
  --server-dir servers/postgres-mcp \
  --machine json
```

The summary schema is `x07.mcp.bundle.summary@0.1.0`. It includes:

- bundle identity, version, transport, and SHA-256
- tool/resource/prompt counts plus task capability flags
- trust and publish-readiness status
- explicit blocker and warning lists
- stable artifact references for the bundle, manifests, and trust metadata
