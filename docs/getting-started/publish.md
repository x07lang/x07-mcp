# Publish dry-run

Use dry-run validation before pushing artifacts to any registry.

## 1) Generate `server.json`

```sh
x07-mcp registry gen \
  --in servers/postgres-mcp/x07.mcp.json \
  --out servers/postgres-mcp/dist/server.json \
  --mcpb servers/postgres-mcp/dist/postgres-mcp.mcpb
```

## 2) Validate artifact + hash

```sh
x07-mcp publish --dry-run \
  --server-json servers/postgres-mcp/dist/server.json \
  --mcpb servers/postgres-mcp/dist/postgres-mcp.mcpb
```

Dry-run checks schema validity, `_meta` limits, and package hash integrity.
