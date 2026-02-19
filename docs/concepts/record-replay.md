# Record/replay

`x07-mcp` ships deterministic replay helpers for stdio, HTTP, and HTTP+SSE cassettes.

## Stdio replay

The stdio format uses two JSONL files:

- client → server lines (`c2s.jsonl`)
- expected server → client lines (`s2c.jsonl`)

Replay runs the shared dispatcher and compares canonicalized JSON responses line-by-line.

## HTTP replay

HTTP replay consumes a single session cassette (`x07.mcp.rr.http_session@0.1.0`) with ordered `steps[]`.

Each step includes:

- `req`: method/path/headers/body
- `res`: expected status/headers/body

Template fixtures live under `tests/.x07_rr/sessions/` and cover:

- initialize + session header flow
- OAuth 401 challenge + PRM discovery
- OAuth 403 insufficient scope
- guardrails for missing session id, invalid protocol version, and `GET /mcp` when SSE is disabled

## HTTP+SSE replay

`std.mcp.rr.http_sse.replay_from_fs_v1` replays deterministic `.http_sse.session.jsonl` cassettes.

Fixtures use:

- `tests/.x07_rr/sessions/http_sse_post_progress_poll_resume.http_sse.session.jsonl`
- `tests/.x07_rr/sessions/http_sse_get_listen_resources_updated.http_sse.session.jsonl`
- `tests/.x07_rr/sessions/http_sse_cancelled_tool_call.http_sse.session.jsonl`
- `tests/.x07_rr/sessions/http_sse_origin_invalid_403.http_sse.session.jsonl`

Replay verifies:

- SSE prime event behavior
- event-id monotonicity and resume behavior from `Last-Event-ID`
- progress emission when requested
- cancellation semantics (no final response after cancel)
- no-broadcast routing constraints

## Tasks replay

The `mcp-server-http-tasks` template includes transport-agnostic JSON-RPC transcript fixtures under `tests/fixtures/rr/` (for example `hello_tasks_progress.jsonl`) and replays them via `ext.mcp.rr.replay_from_fs_v1`.

## Sanitization

`std.mcp.rr.sanitize.sanitize_jsonl_v1` canonicalizes stdio lines.

`std.mcp.rr.sanitize.sanitize_http_session_v1` is the HTTP sanitizer hook used by replay/record pipelines.

`std.mcp.rr.sanitize.sanitize_http_sse_session_v1` is the HTTP+SSE sanitizer hook (headers + token-like values).
