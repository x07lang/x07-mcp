# Server config (`x07.mcp.server_config`)

x07-mcp supports multiple server config schemas.

Pick the schema that matches the transport/server implementation you are using:

- **Current**: `x07.mcp.server_config@0.3.0` (used by `ext.mcp.server`)
- **Legacy**: `x07.mcp.server_config@0.2.0` (used by `std.mcp.transport.http` and `std.mcp.transport.stdio`)

Config files are loaded via `std.mcp.toolkit.server_cfg_file` and validated strictly at startup:

- JSON is canonicalized before parsing.
- Unknown keys and type mismatches are rejected (fail-closed).

Reference servers can materialize effective runtime descriptors before the transport starts. `x07lang-mcp` uses this to write filtered server/tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/` and then launches stdio/HTTP against those generated files.

See:

- `docs/reference/server-config-v0.3.0.md`
- `docs/reference/server-config-v0.2.0.md`
