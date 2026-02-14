# Router/worker model

`x07-mcp` separates concerns:

- **Router** (run-os): transport framing, lifecycle state machine, JSON-RPC dispatch.
- **Worker** (run-os-sandboxed): executes exactly one `tools/call` request under a tool-specific sandbox policy and limits.

This makes it practical to run tools with least privilege while keeping the router small.

## Worker protocol (internal)

The router sends a single JSON object to worker stdin:

- `tool`: tool name
- `ctx`: server config JSON (for shared context)
- `args`: tool arguments JSON
- `tools`: tools manifest JSON

The worker returns a single JSON object containing `toolResult` (MCP `tools/call` result payload).
