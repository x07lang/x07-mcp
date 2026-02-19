# Tasks

MCP Tasks (protocol `2025-11-25`) let the server execute tool calls asynchronously.

## Negotiation

Tasks support is negotiated in two places:

- **Server capability**: `initialize.result.capabilities.tasks` indicates the server implements `tasks/*` methods and can accept task-augmented `tools/call` when `capabilities.tasks.requests.tools.call` is present.
- **Per-tool policy**: each tool descriptor may set `execution.taskSupport`:
  - `forbidden`: task-augmented `tools/call` is rejected
  - `optional`: client may choose task or non-task mode
  - `required`: non-task `tools/call` is rejected

## Lifecycle

- `tools/call` (task mode) returns a `CreateTaskResult` immediately.
- `tasks/get` returns the current task snapshot.
- `tasks/list` returns tasks (newest-first) with cursor pagination.
- `tasks/result` blocks until the task reaches a terminal state and then returns the underlying result (for tool calls: a `CallToolResult`).
- `tasks/cancel` transitions the task to `cancelled` and cancellation is sticky (terminal states never change).

Terminal states:

- `completed`
- `failed`
- `cancelled`

When a task is `cancelled`, `tasks/result` returns a JSON-RPC error `-32000` ("Task cancelled") and includes related-task metadata.

## Scoping

Tasks are scoped to the current auth context (Authorization header hash / session id / stdio). Cross-context `get/list/result/cancel` is rejected or omitted.

## Progress and status

Task-augmented tool calls can opt in to progress via `_meta.progressToken` on the `tools/call` request.

In x07-mcp:

- `_meta.progressToken` must be a JSON string or number; other types are rejected as JSON-RPC invalid params (`-32602`).
- The progress token remains valid for the lifetime of the task.
- `notifications/progress` must stop once the task reaches a terminal state (`completed`, `failed`, `cancelled`).
- `notifications/progress` carries related-task metadata via `_meta["io.modelcontextprotocol/related-task"] = { taskId }`.

Tool code can emit progress in a transport-neutral way (worker → router) using:

- `std.mcp.toolkit.progress.emit_v1(ctx_json, progress_i32, total_i32, message_utf8)`

Tools can also request a `statusMessage` update while a task is still working:

- `std.mcp.toolkit.task.set_status_message_v1(ctx_json, message_utf8)`
