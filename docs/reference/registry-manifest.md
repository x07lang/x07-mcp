# Registry manifest (`x07.mcp.server@0.1.0`)

`x07.mcp.json` is the publish/registry input manifest consumed by `x07-mcp registry gen`.

## Required top-level fields

- `schema_version`: must be `x07.mcp.server@0.1.0`
- `identifier`: registry server name (must contain `mcp`)
- `display_name`
- `version`

At least one of:

- `packages[]` (for bundled/package distribution), or
- `remotes[]` (for remote-only listings)

## `packages[]` (mcpb)

Common fields:

- `registryType`: use `mcpb`
- `identifier`
- `version`
- `url`
- `fileSha256` (64 lowercase hex chars)

When `--mcpb` is passed, `registry gen` computes and writes `fileSha256`.

## `_meta` restrictions

For dry-run validation, `_meta` is limited to:

- `io.modelcontextprotocol.registry/publisher-provided`

Total `_meta` JSON size must stay within `4096` bytes.
