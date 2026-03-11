# Production Readiness Review (2026-03-01) — Claim Verification

This file verifies the claims in `dev-docs/notes/x07-mcp-production-readiness-review-2026-03-01.md`
against the `x07-mcp/` repository contents.

Legend:
- **Verified**: claim matches code/config in the referenced version(s).
- **Refuted**: claim does not match code/config in the referenced version(s).
- **Partial**: claim has a true core but overstates impact or misattributes scope.

Kit defaults (templates/servers in this repo) are pinned to:
- `ext-mcp-auth@0.4.6`
- `ext-mcp-core@0.3.4`
- `ext-mcp-rr@0.3.15`
- `ext-mcp-sandbox@0.3.5`
- `ext-mcp-toolkit@0.3.6`
- `ext-mcp-transport-http@0.3.16`
- `ext-mcp-transport-stdio@0.3.4`
- `ext-mcp-worker@0.3.5`

## P0 — Must Fix

| # | Finding | Status | Evidence | Fix / Notes |
|---|---------|--------|----------|-------------|
| 1 | No tool input JSON Schema validation | **Refuted** | `std.mcp.sandbox.worker_main.run_v1` validates `args_json` via `std.mcp.toolkit.derive_hooks.validate_tool_args_v1` before `mcp.user.call_tool_v1`.<br>`packages/ext/x07-ext-mcp-worker/0.3.4/modules/std/mcp/sandbox/worker_main.x07.json`<br>`packages/ext/x07-ext-mcp-toolkit/0.3.4/modules/std/mcp/toolkit/derive_hooks.x07.json` | N/A |
| 2 | No per-tool-call timeout | **Refuted** | Tool execution is bounded by worker process caps: `std.mcp.sandbox.profiles.tool_caps_v1` calls `std.os.process.caps_v1.finish(..., timeout_ms, ...)`, and router execution passes those caps to `run_capture_v1` / `spawn_piped_v1`.<br>`packages/ext/x07-ext-mcp-sandbox/0.3.5/modules/std/mcp/sandbox/profiles.x07.json`<br>`packages/ext/x07-ext-mcp-sandbox/0.3.5/modules/std/mcp/sandbox/router_exec.x07.json` | N/A |
| 3 | SSE max connections default is unlimited | **Verified** | In `ext-mcp-toolkit@0.3.4`, `transport_http_sse_max_connections_v1` uses default `0` for `transports.http.streamable.sse.max_connections` (key `max_connections`).<br>`packages/ext/x07-ext-mcp-toolkit/0.3.4/modules/std/mcp/toolkit/server_cfg_file.x07.json` | **Fixed**: `ext-mcp-toolkit@0.3.6` defaults to `64`.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/server_cfg_file.x07.json`<br>Templates also set `"max_connections": 64` explicitly (for example `templates/mcp-server-http/config/mcp.server.json`). |
| 4 | SSE drain tasks persist for leaked sessions | **Verified** | In `ext-mcp-transport-http@0.3.13`, session GC removes SSE channel entries without closing the channel handle (drain tasks can remain blocked).<br>`packages/ext/x07-ext-mcp-transport-http/0.3.13/modules/ext/mcp/server.x07.json` | **Fixed** in `ext-mcp-transport-http@0.3.14+`: GC closes the SSE channel handle (`chan.bytes.close`) before removing `sse_chans`.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.14/modules/ext/mcp/server.x07.json` |
| 5 | Stale dist artifact under `ext-mcp-rr@0.3.13/dist/` | **Partial** | `dist/` is ignored at repo level, and no `dist/` files under `packages/ext/x07-ext-mcp-rr/0.3.13/` are tracked by git.<br>`x07-mcp/.gitignore` | If a stale local `dist/` exists, it is not part of this repo’s tracked contents. |
| 6 | Temp files committed (`tmp_*`, `tmp_client_results_*`) | **Refuted** | `tmp*` and `.agent_cache/` are ignored (`x07-mcp/.gitignore`), and conformance results are ignored (`conformance/.gitignore`). No such paths are tracked (`git ls-files`). | N/A |

## P1 — Should Fix

| # | Finding | Status | Evidence | Fix / Notes |
|---|---------|--------|----------|-------------|
| 7 | DPoP `typ` header not validated | **Verified** | In `ext-mcp-auth@0.4.5`, DPoP verification does not enforce `typ="dpop+jwt"`.<br>`packages/ext/x07-ext-mcp-auth/0.4.5/modules/std/mcp/auth/rs_v1.x07.json` | **Fixed**: `ext-mcp-auth@0.4.6` enforces `dpop+jwt`.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/modules/std/mcp/auth/rs_v1.x07.json` |
| 8 | `origin_allow_missing` defaults to true | **Verified** | `ext-mcp-toolkit@0.3.4` defaults to `true` for HTTP origin checks.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.4/modules/std/mcp/toolkit/server_cfg_file.x07.json` | **Fixed**: `ext-mcp-toolkit@0.3.6` defaults to `false`.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/server_cfg_file.x07.json`<br>Templates also set `"origin_allow_missing": false`. |
| 9 | Placeholder `https://mcp.example.com` in default origin allowlist | **Verified** | `origin_allowed_v1` default allowlist includes `https://mcp.example.com` in `ext-mcp-transport-http@0.3.13`.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.13/modules/std/mcp/transport/http_rules.x07.json` | **Fixed**: removed from defaults in `ext-mcp-transport-http@0.3.15`.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.15/modules/std/mcp/transport/http_rules.x07.json` |
| 10 | Missing `aud` claim returns empty bytes (500) instead of 401 | **Verified** | `ext-mcp-auth@0.4.5` returns `bytes.alloc(0)` when the JWT `aud` claim is missing (`aud_off < 0`).<br>`packages/ext/x07-ext-mcp-auth/0.4.5/modules/std/mcp/auth/rs_v1.x07.json` (`_oauth2_authenticate_http_v2_jwt_jwks_v1`) | **Fixed**: `ext-mcp-auth@0.4.6` returns a structured 401 with `error_description="missing aud claim"` and a `WWW-Authenticate` value.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/modules/std/mcp/auth/rs_v1.x07.json` |
| 11 | Concurrency slot leak on task cancellation | **Partial** | Per-request concurrency uses a token channel; returning the token depends on the request task reaching the send-back point (no explicit cancellation-safe cleanup primitive is used).<br>`packages/ext/x07-ext-mcp-transport-http/0.3.13/modules/ext/mcp/server.x07.json` | `ext-mcp-transport-http@0.3.15` refactors request serving and adds more defensive handling, but there is still no explicit cancellation-safe “finally”/defer primitive in the code. |
| 12 | SSE outbox append copies data (not a true ring buffer) | **Verified** | `rb_append_v1` is copy-on-append in `ext-mcp-transport-http@0.3.14`.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.14/modules/std/mcp/transport/http_sse_outbox_v1.x07.json` | **Fixed**: `ext-mcp-transport-http@0.3.15` uses a fixed-capacity representation backed by `std.vec_value` to avoid tail-copy on every append.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.15/modules/std/mcp/transport/http_sse_outbox_v1.x07.json` |
| 13 | Full response buffering for JSON-RPC responses | **Verified** | JSON-RPC response builders return a single `bytes` payload (for example `std.mcp.jsonrpc.make_result_response_v1`).<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/jsonrpc.x07.json` | Not fixed (requires streaming response design changes). |
| 14 | No HTTP keep-alive for POST | **Verified** | `ext-mcp-transport-http@0.3.14` closes the TCP stream after each response (`std.net.tcp.stream_close_v1`).<br>`packages/ext/x07-ext-mcp-transport-http/0.3.14/modules/ext/mcp/server.x07.json` | **Fixed**: `ext-mcp-transport-http@0.3.15` supports keep-alive where appropriate.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.15/modules/ext/mcp/server.x07.json` |
| 15 | Double JSON parse per message | **Verified** | `std.mcp.jsonrpc.parse_line_v1` canonicalizes then parses in `ext-mcp-core@0.2.1`.<br>`packages/ext/x07-ext-mcp-core/0.2.1/modules/std/mcp/jsonrpc.x07.json` | **Fixed**: `ext-mcp-core@0.3.4` parses once (no `ext.json.canon.canonicalize` call).<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/jsonrpc.x07.json` |
| 16 | JSON Schema validation is compiled per call (not cached) | **Verified** | `validate_tool_args_v1` calls `ext.jsonschema.compile_v1` on every validation for non-subset schemas.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/derive_hooks.x07.json` | Not fixed (the worker is executed as a one-shot process per tool call, so caching would require architectural changes). |
| 17 | No cursor pagination for tools/resources/prompts list | **Verified** | `ext-mcp-toolkit@0.3.4` list results do not include `nextCursor` and do not accept a cursor.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.4/modules/std/mcp/toolkit/tools_file.x07.json` | **Fixed**: `ext-mcp-toolkit@0.3.6` adds cursor input + `nextCursor` output for `tools_list_result_v1`, `resources_list_result_v1`, and `prompts_list_result_v1`.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/tools_file.x07.json` |
| 18 | Dev config disables auth entirely (`.agent_cache/`) | **Partial** | `.agent_cache/` is ignored and not shipped (`x07-mcp/.gitignore`). | Kit defaults use `"auth": { "mode": "oauth2" }` (for example `templates/mcp-server-http/config/mcp.server.json`). |
| 19 | Release guard doesn’t check for `fixed_v1` clock | **Verified** | Prior guard scripts did not reject `obs.clock.kind == fixed_v1` in non-demo configs. | **Fixed**: `scripts/ci/release_guard_trust_lock_and_sig.sh` rejects fixed clocks outside demo/tests, and a demo config is provided at `templates/mcp-server-http/config/mcp.oauth.demo.json`. |

## P2 — Low Priority

| # | Finding | Status | Evidence | Fix / Notes |
|---|---------|--------|----------|-------------|
| 20 | No CORS response headers | **Verified** | `ext-mcp-transport-http@0.3.13` contains no `Access-Control-*` headers in the SSE head or streamable responses. | **Fixed**: `ext-mcp-transport-http@0.3.15` adds CORS handling and preflight support.<br>`packages/ext/x07-ext-mcp-transport-http/0.3.15/modules/std/mcp/transport/http_sse_outbox_v1.x07.json` |
| 21 | No security headers (X-Content-Type-Options, HSTS, etc.) | **Partial** | `ext-mcp-transport-http@0.3.13` does not emit common security headers. | `ext-mcp-transport-http@0.3.15` adds `X-Content-Type-Options`, `X-Frame-Options`, and `Referrer-Policy`, but does not add HSTS at this layer. |
| 22 | No per-client rate limiting | **Verified** | `ext-mcp-transport-http@0.3.13` has global concurrency limiting but no per-client inflight limiting. | **Fixed**: `ext-mcp-transport-http@0.3.15` adds per-client inflight limiting (`per_client_limit` / `client_inflight`).<br>`packages/ext/x07-ext-mcp-transport-http/0.3.15/modules/ext/mcp/server.x07.json` |
| 23 | Cooperative-only cancellation | **Partial** | Tool logic is cooperative, but the sandbox router can forcibly terminate the worker process. | `std.mcp.sandbox.router_exec._cancel_sender_v1` sends a cancel line and then SIGKILLs the worker (`std.os.process.kill_v1 ... 9`).<br>`packages/ext/x07-ext-mcp-sandbox/0.3.5/modules/std/mcp/sandbox/router_exec.x07.json` |
| 24 | TTL cache has no max-entries enforcement | **Verified** | `ext-mcp-core@0.3.3` TTL cache exports only unbounded `put_bytes_v1`.<br>`packages/ext/x07-ext-mcp-core/0.3.3/modules/std/mcp/cache/ttl_bytes_v1.x07.json` | **Fixed**: `ext-mcp-core@0.3.4` adds `put_bytes_bounded_v1`.<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/cache/ttl_bytes_v1.x07.json` |
| 25 | Python `__pycache__` files in git | **Refuted** | No `__pycache__` paths are tracked (`git ls-files | rg __pycache__`). | N/A |
| 26 | Conformance results accumulating in git | **Refuted** | `conformance/results/` is ignored (`conformance/.gitignore`) and not tracked. | N/A |
| 27 | Limited x07diag codes (only 3) | **Verified** | `ext-mcp-core@0.3.3` exports only `BAD_REQUEST`, `INTERNAL`, and `INVALID_ARGS` codes.<br>`packages/ext/x07-ext-mcp-core/0.3.3/modules/std/mcp/diag.x07.json` | **Fixed**: `ext-mcp-core@0.3.4` adds additional codes (`unauthorized`, `forbidden`, `rate_limited`, `timeout`, `transport`, `sandbox`).<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/diag.x07.json` |
| 28 | Silent empty-bytes error propagation | **Partial** | Some error construction paths use empty-bytes sentinels (for example older `diag_v1` returned `bytes.alloc(0)` on failure). | `ext-mcp-core@0.3.4` improves error JSON construction by using a JSON fallback (`{}`) and omitting empty fields, reducing the number of “empty-bytes” fallbacks. |
| 29 | Conformance client-x07 has only trivial smoke test | **Verified** | `conformance/client-x07/tests/tests.json` previously only exercised a single smoke run. | **Fixed**: added protocol-level unit tests in `conformance/client-x07/tests/app_unit.x07.json` and expanded `conformance/client-x07/tests/tests.json`. |
| 30 | Trust package `requires_packages` uses older dep versions | **Verified** | `ext-mcp-trust@0.5.0` lists `ext-data-model@0.1.8`, `ext-json-rs@0.1.4`, etc.<br>`packages/ext/x07-ext-mcp-trust/0.5.0/x07-package.json` | Low severity; workspace pins newer patch-level deps in `x07.json`. |

## Token Efficiency Findings

| # | Finding | Status | Evidence | Fix / Notes |
|---|---------|--------|----------|-------------|
| T1 | Dual `content` + `structuredContent` | **Partial** | Tool results always include `content`, and may include `structuredContent` when a structured payload is provided (`ok_text_structured_v1` / `err_text_structured_v1`).<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/tool/result.x07.json` | Not fixed (no client capability negotiation to gate structured output). |
| T2 | Error diagnostic verbosity (constant `type`, empty `suggested_fix`) | **Verified** | `ext-mcp-core@0.3.3` always emitted `type` and `suggested_fix` (even empty).<br>`packages/ext/x07-ext-mcp-core/0.3.3/modules/std/mcp/tool/errors.x07.json` | **Fixed**: `ext-mcp-core@0.3.4` omits `type` and conditionally includes `suggested_fix` only when non-empty.<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/tool/errors.x07.json` |
| T3 | Progress notification overhead (no batching/stride) | **Verified** | Progress notifications are emitted as individual JSON-RPC notifications; no stride/batching configuration exists in the toolkit progress helpers.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/progress.x07.json` | Not fixed (would require API/config changes). |
| T4 | No pagination | **Verified** | Same underlying issue as P1#17 in `ext-mcp-toolkit@0.3.4`. | **Fixed** in `ext-mcp-toolkit@0.3.6` (cursor + `nextCursor`). |
| T5 | No description length guardrails | **Verified** | `ext-mcp-toolkit@0.3.4` does not bound tool description length during tools manifest load. | **Fixed**: `ext-mcp-toolkit@0.3.6` enforces a max description length (default `1024`).<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/tools_file.x07.json` |

## Positive Findings — Claim Verification

| Claim | Status | Evidence / Notes |
|-------|--------|------------------|
| JWT validation chain is complete (`iss`, `aud`, `exp`, `nbf`, signature) | **Verified** | Validation checks include `iss`, `aud`, `exp`, and `nbf` handling in `std.mcp.auth.rs_v1` JWT/JWKS flow.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/modules/std/mcp/auth/rs_v1.x07.json` |
| DPoP binding is correct (incl. replay detection window) | **Verified** | DPoP proof validation and replay map maintenance exist in `std.mcp.auth.rs_v1` (`dpop_replay`, `jti`, window enforcement).<br>`packages/ext/x07-ext-mcp-auth/0.4.6/modules/std/mcp/auth/rs_v1.x07.json` |
| SSRF guard blocks private/loopback/link-local/CGNAT and requires HTTPS | **Verified** | Strict guard enforces `https` and rejects relevant IP ranges.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/modules/std/mcp/auth/ssrf_guard_v1.x07.json` |
| SQL injection prevention via parameterized queries | **Verified** | SQLite access uses numbered parameters (`?1`, `?2`, ...).<br>`packages/ext/x07-ext-mcp-sandbox/0.3.5/modules/std/mcp/sandbox/task_store_sqlite_v1.x07.json` |
| Session isolation (`auth_context_id` in primary keys) | **Verified** | `mcp_tasks` uses `PRIMARY KEY(auth_context_id, task_id)`.<br>`packages/ext/x07-ext-mcp-sandbox/0.3.5/modules/std/mcp/sandbox/task_store_sqlite_v1.x07.json` |
| Secret redaction configurable + depth-limited | **Verified** | Redaction supports key + regex patterns and bounds recursion depth.<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/redact.x07.json` |
| Stdio stdout cleanliness | **Verified** | JSON-RPC is written to stdout and flushed; stderr is separate and flushed.<br>`packages/ext/x07-ext-mcp-transport-stdio/0.3.4/modules/std/mcp/transport/stdio_loop.x07.json` |
| PRM signing/verification implemented | **Verified** | PRM signed flows are implemented and tested in `ext-mcp-auth`.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/tests/tests.json` |
| Trust packages have “38+ tests” for Merkle/TUF/rollback | **Partial** | `ext-mcp-trust@0.5.0` has 25 tests, and `packages/app/x07-mcp/0.4.1` has 12 publish/trust-pack tests (total 37). Coverage of Merkle/TUF/rollback is present. |
| CI pipeline has “20+” gates incl. security + lock checks | **Partial** | `scripts/ci/check_all.sh` includes security test runs and lock/pin verification; exact gate count not audited here. |
| Safe production defaults (localhost bind, OAuth2 on, redaction on, sandbox on) | **Verified** | HTTP template uses localhost bind and OAuth2; redaction and sandbox per-tool are enabled by default.<br>`templates/mcp-server-http/config/mcp.server.json` |
| No TODO/FIXME/HACK markers in shipped code | **Verified** | `rg \"TODO|FIXME|HACK\"` across repo does not match under `packages/`, `cli/`, `servers/`, `templates/`, `docs/`, `scripts/`, `conformance/`. |
| Lockfile integrity (hashes/yanked/overrides) | **Partial** | Lockfiles contain integrity metadata and CI gates enforce lock checks; this document does not re-audit every lock entry. |
| `make_result_response_trusted_v1` fast path exists | **Verified** | `std.mcp.jsonrpc.make_result_response_trusted_v1` uses a fast path when no newlines are present.<br>`packages/ext/x07-ext-mcp-core/0.3.4/modules/std/mcp/jsonrpc.x07.json` |
| RR sanitizer is fail-closed | **Verified** | RR tests include fail-closed behavior for unexpected tokens.<br>`packages/ext/x07-ext-mcp-rr/0.3.15/tests/tests.json` |
| Concurrency model is bounded (`max_concurrent_requests=128`, `max_children=1024`) | **Verified** | Default `max_concurrent_requests` is 128 in toolkit config parsing; HTTP server uses `task.scope.cfg_v1(max_children=1024)`.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/server_cfg_file.x07.json`<br>`packages/ext/x07-ext-mcp-transport-http/0.3.16/modules/ext/mcp/server.x07.json` |
| SSE streaming and outbox replay exist | **Verified** | SSE uses chunked transfer and sequence-based replay helpers (`rb_write_after_seq_v1`).<br>`packages/ext/x07-ext-mcp-transport-http/0.3.16/modules/std/mcp/transport/http_sse_outbox_v1.x07.json` |
| Config validation is thorough and runs at startup | **Partial** | Config load runs strict schema checks and field validators; the “76KB” sizing detail is not verified here.<br>`packages/ext/x07-ext-mcp-toolkit/0.3.6/modules/std/mcp/toolkit/server_cfg_file.x07.json` |

## Security Test Coverage Gaps — Claim Verification

| Claim | Status | Evidence / Notes |
|-------|--------|------------------|
| Existing coverage items listed are present | **Verified** | Auth/DPoP/SSRF/introspection/PRM coverage exists in `ext-mcp-auth` tests; origin + transport flows exist in `ext-mcp-transport-http` tests.<br>`packages/ext/x07-ext-mcp-auth/0.4.6/tests/tests.json`<br>`packages/ext/x07-ext-mcp-transport-http/0.3.16/tests/tests.json` |
| “Missing coverage” items are absent | **Partial** | Several items are clearly absent (expired JWT, wrong `iss`, wrong `aud`, `nbf` in future, origin validation with `origin_allow_missing=0`). This document does not exhaustively prove absence for every listed item. |
