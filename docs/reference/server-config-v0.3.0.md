# Server config (`x07.mcp.server_config@0.3.0`)

This schema is used by:

- `ext.mcp.server` (Streamable HTTP router)
- templates: `templates/mcp-server-http/`, `templates/mcp-server-http-tasks/`

The server config JSON declares:

- server identity (`server.*`)
- auth policy (`auth.*`)
- transports (currently `transports.http.*`)
- tool descriptor path (`tools.descriptor_path`)
- worker executable path (`worker_exe_path`)
- tasks capability + stores/executors (`capabilities.tasks.*`, `tasks.*`)
- observability (`observability.*`)
- per-tool sandbox policy wiring (`sandbox.per_tool.*`)

## Root

- `schema_version`: must be `x07.mcp.server_config@0.3.0`

## `server`

- `server.name`: string
- `server.version`: string
- `server.protocolVersion`: string (for MCP 2025-11-25 servers: `2025-11-25`)

## `auth`

- `auth.mode`: `none` | `oauth2`
- `auth.oauth_config_path`: string (path to `mcp.oauth.json`)
- `auth.required_scopes`: array of scopes (strings)
- `auth.required_scopes_tasks`: array of scopes (strings)

## `transports.http`

- `transports.http.enabled`: boolean
- `transports.http.bind`: string (`"host:port"`)
- `transports.http.path`: string (default templates use `"/mcp"`)
- `transports.http.origin_allow_missing`: boolean
- `transports.http.origin_allowlist`: array of origin patterns (strings)

### `transports.http.streamable`

- `transports.http.streamable.enabled`: boolean

#### `transports.http.streamable.sse`

- `transports.http.streamable.sse.enabled`: boolean
- `transports.http.streamable.sse.max_connections`: number

#### `transports.http.streamable.session`

- `transports.http.streamable.session.mode`: `optional` | `required`
- `transports.http.streamable.session.ttl_seconds`: number
- `transports.http.streamable.session.max`: number

## `tools`

- `tools.descriptor_path`: string (path to `mcp.tools.json`)

## `worker_exe_path`

- `worker_exe_path`: string (path to the bundled worker executable)

## `observability`

### `observability.clock`

- `observability.clock.mode`: `os_now` | `fixed`
- `observability.clock.fixed.utc_iso8601`: RFC3339 string

### `observability.logging`

- `observability.logging.enabled`: boolean
- `observability.logging.declare_capability`: boolean
- `observability.logging.default_client_level`: string
- `observability.logging.client_level_floor`: string
- `observability.logging.rate_limit_per_sec`: number
- `observability.logging.max_data_bytes`: number

#### `observability.logging.emit`

- `observability.logging.emit.tool_start`: boolean
- `observability.logging.emit.tool_finish`: boolean

#### `observability.logging.redaction`

- `observability.logging.redaction.redact_keys`: array of strings
- `observability.logging.redaction.redact_patterns`: array of regex strings
- `observability.logging.redaction.redacted_value`: string

### `observability.audit`

- `observability.audit.enabled`: boolean
- `observability.audit.sinks`: array of sinks
- `observability.audit.allow_tool_tags`: array of strings

### `observability.metrics`

- `observability.metrics.enabled`: boolean
- `observability.metrics.flush_interval_ms`: number

#### `observability.metrics.export`

- `observability.metrics.export.kind`: string
- `observability.metrics.export.arch_exporter_id`: string

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
