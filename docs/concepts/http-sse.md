# HTTP SSE

`ext-mcp-transport-http@0.2.0` adds Streamable HTTP SSE for MCP request/notification delivery.

## Modes

- `POST /mcp` can return:
  - `application/json` (single response), or
  - `text/event-stream` (streamed response flow).
- `GET /mcp` with `Accept: text/event-stream` opens a listen stream for server notifications.

## Event framing and IDs

- SSE framing is shared via `std.mcp.sse`:
  - `std.mcp.sse.encode_event_v1`
  - `std.mcp.sse.encode_retry_v1`
- Event IDs use:
  - `<sessionId>/<streamKind>/<streamKey>/<seq>`
  - `streamKind`: `post`, `get_listen`, `get_resume`
- `Last-Event-ID` resumes from bounded ring buffers keyed by stream identity.

## Routing invariants

- No-broadcast routing is enforced:
  - request-scoped notifications (including progress) stay on the request stream,
  - `notifications/resources/updated` is delivered to listen streams for subscribed URIs.

## Progress and cancellation

- `_meta.progressToken` on `tools/call` enables `notifications/progress`.
- `notifications/cancelled` cancels an in-flight request explicitly.
- Disconnect is not treated as cancellation.
- Cancelled tool calls produce no final response event.

## Security

- Origin checks are applied to both `POST /mcp` and `GET /mcp`.
- Invalid Origin is rejected with HTTP `403`.
