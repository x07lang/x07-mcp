# Packages

`x07-mcp` publishes these MCP kit packages:

- `ext-mcp-core@0.3.1`: protocol constants, JSON-RPC helpers, diagnostics, progress token registry, SSE/event-id helpers
- `ext-mcp-toolkit@0.3.1`: server/tools manifest loaders, schema helpers, shared dispatcher, tool context helpers, progress/status emit APIs
- `ext-mcp-worker@0.3.1`: worker protocol + worker entrypoint
- `ext-mcp-sandbox@0.3.1`: router-side sandbox + task stores/executors + worker spawn helpers (streaming/cancel-aware)
- `ext-mcp-transport-stdio@0.3.0`: stdio MCP transport (tasks, progress, cancellation, subscriptions)
- `ext-mcp-transport-http@0.3.1`: HTTP MCP transport + Streamable HTTP SSE
- `ext-mcp-auth@0.1.0`: OAuth test-static validation + challenge/PRM helpers
- `ext-mcp-obs@0.1.0`: audit JSONL + metrics hooks
- `ext-mcp-rr@0.3.1`: deterministic stdio, HTTP, and HTTP+SSE replay helpers + sanitizers
