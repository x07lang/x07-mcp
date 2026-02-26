# Packages

`x07-mcp` publishes these MCP kit packages:

- `ext-mcp-core@0.3.2`: protocol constants, JSON-RPC helpers, diagnostics, progress token registry, SSE/event-id helpers
- `ext-mcp-toolkit@0.3.3`: server/tools manifest loaders, schema helpers, shared dispatcher, tool context helpers, progress/status emit APIs
- `ext-mcp-worker@0.3.3`: worker protocol + worker entrypoint
- `ext-mcp-sandbox@0.3.3`: router-side sandbox + task stores/executors + worker spawn helpers (streaming/cancel-aware)
- `ext-mcp-transport-stdio@0.3.2`: stdio MCP transport (tasks, progress, cancellation, subscriptions)
- `ext-mcp-transport-http@0.3.9`: HTTP MCP transport (`ext.mcp.server`) + Streamable HTTP SSE
- `ext-mcp-transport-http@0.2.1`: HTTP MCP transport (`std.mcp.transport.http`) for the legacy server config (`x07.mcp.server_config@0.2.0`)
- `ext-mcp-auth-core@0.1.1`: pure PRM URL/JSON utilities, Bearer parsing, `WWW-Authenticate` formatting, scope set ops
- `ext-mcp-auth@0.4.1`: OAuth2 resource server enforcement (introspection + JWT/JWKS) + DPoP + DPoP nonce + signed PRM metadata (HS256 + Ed25519/RS256 with trust anchors) (uses `ext-mcp-auth-core`)
- `ext-mcp-trust@0.1.0`: pure trust-framework parsing/validation, resource policy resolution (`exact`/`prefix`/`hostSuffix`), issuer key resolution, and deterministic framework SHA-256 fingerprinting
- `ext-mcp-obs@0.1.3`: audit JSONL + metrics hooks
- `ext-mcp-rr@0.3.9`: deterministic stdio, HTTP, and HTTP+SSE replay helpers + sanitizers

## Lockfiles

`x07-mcp` tracks the published `packages/ext/` tree via `locks/external-packages.lock`. CI checks that the lockfile matches the on-disk packages.

Regenerate:

```bash
python3 scripts/generate_external_packages_lock.py --packages-root packages/ext --out locks/external-packages.lock --write
```
