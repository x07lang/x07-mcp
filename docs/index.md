# x07-mcp

`x07-mcp` is the MCP kit for X07. It provides:

- a **stdio MCP server** implementation (JSON-RPC 2.0, newline-delimited)
- an **HTTP MCP server** with Streamable HTTP + SSE support
- a **router/worker** execution model for tools (per-tool sandbox policies + limits)
- a **tools manifest** format (tool metadata + schemas + X07 execution metadata)
- **OAuth 2.1 resource-server** helpers (RFC 9728, DPoP, scope-to-tool mapping)
- a **record/replay** helper for deterministic golden transcripts
- a **trust transparency monitor** surface (append-only tlog checks + policy alerts)
- a **conformance runner** for MCP protocol compliance testing
- a **publish** pipeline with trust packs, anti-rollback, and dry-run validation

The implementation is pinned to MCP protocol version `2025-11-25` (negotiated during `initialize`).

## Getting started

- [Install](getting-started/install.md)
- [Scaffold a server](getting-started/scaffold.md)
- [Run a stdio server](getting-started/run-stdio.md)
- [Run an HTTP server](getting-started/run-http.md)
- [Run conformance](getting-started/conformance.md)
- [Build `.mcpb` bundles](getting-started/bundle-mcpb.md)
- [Publish dry-run](getting-started/publish.md)
- [Trust tlog monitor](getting-started/trust-tlog-monitor.md)

## Concepts

- [Router/worker model](concepts/router-worker.md)
- [Tool schemas](concepts/tool-schemas.md)
- [Sandbox policy & limits](concepts/sandbox.md)
- [Tasks](concepts/tasks.md)
- [Record/replay](concepts/record-replay.md)
- [HTTP SSE](concepts/http-sse.md)

## Reference

- [Server config](reference/server-config.md)
- [OAuth config](reference/oauth-config.md)
- [Tools manifest](reference/tools-manifest.md)
- [Resources manifest](reference/resources-manifest.md)
- [Prompts manifest](reference/prompts-manifest.md)
- [Registry manifest](reference/registry-manifest.md)
- [Reference servers](reference/servers.md)
- [Packages](reference/packages.md)
- [Pins](reference/pins.md)
