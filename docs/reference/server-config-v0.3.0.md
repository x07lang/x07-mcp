# Server config (`x07.mcp.server_config@0.3.0`)

The server config JSON declares:

- `server.name`, `server.version`, `server.protocolVersion`
- `transports.http.*` (HTTP bind/path + streamable settings)
- `tools.descriptor_path` (tools manifest path)
- `capabilities.tasks` (and whether `tools/call` supports `task`)
- `tasks.*` (defaults, id/clock/executor modes, retention, store)
- `sandbox.per_tool.*` (worker sandbox policy wiring)

## Root

- `schema_version`: must be `x07.mcp.server_config@0.3.0`

## `server`

- `server.name`: string
- `server.version`: string
- `server.protocolVersion`: string (for Phase 5: `2025-11-25`)

## `transports.http`

- `transports.http.enabled`: boolean
- `transports.http.bind`: string (`"host:port"`)
- `transports.http.path`: string (default templates use `"/mcp"`)
- `transports.http.streamable.enabled`: boolean
- `transports.http.streamable.sse.enabled`: boolean
- `transports.http.streamable.sse.max_connections`: number

## `tools`

- `tools.descriptor_path`: string (path to `mcp.tools.json`)

## `capabilities`

For Tasks, the router enforces negotiation using the `initialize` capabilities payload:

- `capabilities.tasks` present: server implements `tasks/*`
- `capabilities.tasks.requests.tools.call` present: server accepts task-augmented `tools/call`

## `tasks`

- `tasks.enabled`: boolean
- `tasks.defaults.ttl_ms`: number (stored and echoed in task snapshots)
- `tasks.defaults.poll_interval_ms`: number (stored and echoed in task snapshots)

### `tasks.id`

- `tasks.id.mode`: `deterministic` | `random`
- `tasks.id.deterministic.prefix`: string
- `tasks.id.deterministic.start`: number

### `tasks.clock`

- `tasks.clock.mode`: `fixed` | `os_now`
- `tasks.clock.fixed.start_iso8601`: RFC3339 string
- `tasks.clock.fixed.step_ms`: number

### `tasks.executor`

- `tasks.executor.mode`: `deterministic` | `async_pool`
- `tasks.executor.deterministic.complete_after_ticks`: number
- `tasks.executor.deterministic.advance_on`: array of JSON-RPC method names (strings)

### `tasks.retention`

- `tasks.retention.max_tasks`: number

### `tasks.notifications` (optional)

- `tasks.notifications.status`: boolean (emit `notifications/tasks/status` on transitions; defaults to enabled)

### `tasks.store` (optional)

- `tasks.store.mode`: `mem` | `sqlite` (when omitted, mem is used)
- `tasks.store.sqlite.path`: string (sqlite DB file path)

## `sandbox.per_tool`

- `sandbox.per_tool.enabled`: boolean
- `sandbox.per_tool.policy_path`: string (policy JSON for worker isolation)

