# Changelog

## Unreleased

- x07-mcp CLI implemented in X07 (bundled via `x07 bundle`).
- `x07lang-mcp` extended to a pack-gated `0.2.0` surface with ecosystem, package, wasm, web-ui, device, app, and platform tools.
- `ext-mcp-toolkit@0.3.8`, `ext-mcp-transport-stdio@0.3.7`, `ext-mcp-transport-http@0.3.18`, `ext-mcp-rr@0.3.17`, and `ext-mcp-sandbox@0.3.11` add runtime descriptor loading and pack-oriented sandbox/limits support.
- `ext-mcp-toolkit@0.3.9` fixes stdio `initialize` negotiation so MCP clients using `2025-03-26` or `2025-06-18` can start successfully against `2025-11-25` servers.
- `ext-mcp-toolkit@0.3.10`, `ext-mcp-sandbox@0.3.12`, `ext-mcp-transport-stdio@0.3.8`, and `ext-mcp-transport-http@0.3.19` republish the current runtime-descriptor and stdio-negotiation bytes under fresh immutable versions, and CI now checks patched project locks against a clean registry-only graph before the local-deps guard.
- `ext-mcp-transport-http@0.3.20` fixes the HTTP session follow-up crash in the per-client inflight limiter and refreshes all repo-owned HTTP MCP server templates/locks to that package line.

## 0.1.0

- Initial release of `ext-mcp-*` packages and stdio server template.
