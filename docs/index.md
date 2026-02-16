# x07-mcp

`x07-mcp` is the MCP kit for X07. It provides:

- a **stdio MCP server** implementation (JSON-RPC 2.0, newline-delimited)
- a **router/worker** execution model for tools (per-tool sandbox policies + limits)
- a **tools manifest** format (tool metadata + schemas + X07 execution metadata)
- a **record/replay** helper for deterministic golden transcripts

The implementation is pinned to MCP protocol version `2025-11-25` (negotiated during `initialize`).

Start here:

- [Install](getting-started/install.md)
- [Scaffold a server](getting-started/scaffold.md)
- [Run a stdio server](getting-started/run-stdio.md)
- [Run conformance](getting-started/conformance.md)
- [Build `.mcpb` bundles](getting-started/bundle-mcpb.md)
