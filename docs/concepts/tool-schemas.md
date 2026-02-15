# Tool schemas

Each tool in `config/mcp.tools.json` includes `inputSchema` (JSON Schema). The worker compiles and validates schemas using `ext-jsonschema-rs`:

- default dialect is **JSON Schema 2020-12** when `$schema` is absent
- `$schema` overrides are honored when supported
- unsupported dialects fail with a clear, deterministic error

If argument validation fails, the worker returns an MCP tool error (`isError: true`) with structured diagnostics and deterministic error ordering.
