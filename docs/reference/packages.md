# Packages

`x07-mcp` publishes these MCP kit packages:

- `ext-mcp-core@0.3.4`: protocol constants, JSON-RPC helpers, diagnostics, progress token registry, SSE/event-id helpers
- `ext-mcp-toolkit@0.3.10`: server/tools/resources/prompts loaders, descriptor-path aware server config helpers, shared dispatcher, tool context helpers, progress/status emit APIs, and stdio initialize negotiation for `2025-11-25`, `2025-06-18`, and `2025-03-26`
- `ext-mcp-worker@0.3.5`: worker protocol + worker entrypoint
- `ext-mcp-sandbox@0.3.12`: router-side sandbox + task stores/executors + worker spawn helpers (streaming/cancel-aware), custom limits profiles, and per-tool process allowlists
- `ext-mcp-transport-stdio@0.3.8`: stdio MCP transport (tasks, progress, cancellation, subscriptions) with runtime descriptor-path support
- `ext-mcp-transport-http@0.3.21`: HTTP MCP transport (`ext.mcp.server`) + Streamable HTTP SSE with runtime descriptor-path support and the `ext-net@0.1.10` package line
- `ext-mcp-transport-http@0.2.1`: HTTP MCP transport (`std.mcp.transport.http`) for the legacy server config (`x07.mcp.server_config@0.2.0`)
- `ext-mcp-auth-core@0.1.2`: pure PRM URL/JSON utilities, Bearer parsing, `WWW-Authenticate` formatting, scope set ops
- `ext-mcp-auth@0.4.7`: OAuth2 resource server enforcement (introspection + JWT/JWKS) + DPoP + DPoP nonce + signed PRM metadata (HS256 + Ed25519/RS256 with trust anchors) (uses `ext-mcp-auth-core` and the `ext-net@0.1.10` package line)
- `ext-mcp-trust@0.5.0`: trust framework v3 + lock v2 + TUF-lite registry metadata verification + anti-rollback + transparency tlog verification (`checkpoint_jws`, inclusion/consistency proofs, bundle verification, monitor policy)
- `ext-mcp-trust@0.4.0`: trust framework v3 + lock v2 + TUF-lite registry metadata verification + anti-rollback state helpers + witness checkpoint verification + secure semver resolution
- `ext-mcp-trust@0.3.0`: trust framework v3 + lock v2 + remote-source validation + trust-pack registry/semver resolution + lock-pinned bundle verification
- `ext-mcp-trust@0.2.0`: trust framework/bundle parsing + signed trust bundle statement verification + trust lock validation + deterministic authorization server selection (`prefer_order_v1`)
- `ext-mcp-trust@0.1.0`: phase-12 trust framework parsing/validation and issuer key resolution surface retained for compatibility
- `ext-mcp-trust-os@0.5.1`: run-os trust adapters for TUF-lite + transparency monitor execution (`get-sth`, consistency fetch, checkpoint state store, monitor runner)
- `ext-mcp-trust-os@0.4.0`: run-os trust adapters for TUF-lite metadata/witness verification + trust state fs store + cached remote fetch helpers
- `ext-mcp-trust-os@0.3.0`: run-os trust adapters for cached remote bundle fetch (`http_fetch_cached_v1`) + content-addressed fs cache + SSRF policy v2
- `ext-mcp-trust-os@0.1.0`: run-os trust adapters (bundle fetch + authorization server metadata fetch/validation)
- `x07-mcp@0.4.3` (app package): trust-pack install/update + publish trust-pack validation/meta summary + trust tlog monitor command surface (`app.mcp.cli.trust_tlog_monitor_v1`)
- `x07-mcp@0.3.0` (app package): trust-pack install/update phase-15 helpers + publish trust-pack validation/meta summary v3 (`minSnapshotVersion`, `snapshotSha256`, `checkpointSha256`)
- `ext-mcp-obs@0.1.4`: audit JSONL + metrics hooks
- `ext-mcp-rr@0.3.19`: deterministic stdio, HTTP, and HTTP+SSE replay helpers + sanitizers aligned to the latest auth + HTTP transport package line

## Lockfiles

`x07-mcp` tracks the published `packages/ext/` tree via `locks/external-packages.lock`. CI checks that the lockfile matches the on-disk packages.

Regenerate:

```bash
python3 scripts/generate_external_packages_lock.py --packages-root packages/ext --out locks/external-packages.lock --write
```
