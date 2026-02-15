# Record/replay

`x07-mcp` ships deterministic replay helpers for stdio and HTTP cassettes.

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

Template fixtures live under `tests/fixtures/rr/http/` and cover:

- initialize + session header flow
- OAuth 401 challenge + PRM discovery
- OAuth 403 insufficient scope
- guardrails for missing session id, invalid protocol version, and `GET /mcp` when SSE is disabled

## Sanitization

`std.mcp.rr.sanitize.sanitize_jsonl_v1` canonicalizes stdio lines.

`std.mcp.rr.sanitize.sanitize_http_session_v1` is the HTTP sanitizer hook used by replay/record pipelines.
