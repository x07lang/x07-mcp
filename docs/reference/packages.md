# Packages

`x07-mcp` publishes these MCP kit packages:

- `ext-mcp-core@0.3.2`: protocol constants, JSON-RPC helpers, diagnostics, progress token registry, SSE/event-id helpers
- `ext-mcp-toolkit@0.3.2`: server/tools manifest loaders, schema helpers, shared dispatcher, tool context helpers, progress/status emit APIs
- `ext-mcp-worker@0.3.2`: worker protocol + worker entrypoint
- `ext-mcp-sandbox@0.3.2`: router-side sandbox + task stores/executors + worker spawn helpers (streaming/cancel-aware)
- `ext-mcp-transport-stdio@0.3.0`: stdio MCP transport (tasks, progress, cancellation, subscriptions)
- `ext-mcp-transport-http@0.3.3`: HTTP MCP transport (`ext.mcp.server`) + Streamable HTTP SSE
- `ext-mcp-transport-http@0.2.1`: HTTP MCP transport (`std.mcp.transport.http`) for the legacy server config (`x07.mcp.server_config@0.2.0`)
- `ext-mcp-auth-core@0.1.0`: pure PRM URL/JSON utilities, Bearer parsing, `WWW-Authenticate` formatting, scope set ops
- `ext-mcp-auth@0.2.0`: OAuth2 resource server enforcement + introspection adapter (uses `ext-mcp-auth-core`)
- `ext-mcp-obs@0.1.1`: audit JSONL + metrics hooks
- `ext-mcp-rr@0.3.3`: deterministic stdio, HTTP, and HTTP+SSE replay helpers + sanitizers
