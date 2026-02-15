# Packages

`x07-mcp` ships a small set of X07 external packages:

- `ext-mcp-core@0.1.1`: protocol constants, JSON-RPC helpers, diagnostics, tool result helpers
- `ext-mcp-toolkit@0.1.1`: server config + tools manifest loaders, schema validation helpers, shared stdio dispatcher
- `ext-mcp-worker@0.1.1`: worker protocol + worker entrypoint (validates args, calls tool implementation)
- `ext-mcp-transport-stdio@0.1.1`: stdio MCP server (router)
- `ext-mcp-sandbox@0.1.1`: router-side tool execution helpers (policy env + spawn + limits)
- `ext-mcp-rr@0.1.1`: record/replay helpers (stdio JSONL replay, sanitization)
