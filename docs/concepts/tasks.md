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

