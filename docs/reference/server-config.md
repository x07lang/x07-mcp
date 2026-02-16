# Server config (`x07.mcp.server_config@0.2.0`)

The server config JSON declares:

- `server.name`, `server.version`, `server.protocolVersion`
- `tools_manifest_path`: path to the tools manifest JSON
- `worker_exe_path`: path to the bundled worker executable
- `transport.kind`: `stdio` or `http`

Common sections:

- `budgets.index_path`, `budgets.default_profile`
- `sandbox.router_base_policy_path`, `sandbox.worker_base_policy_path`
- `rr.enabled`, `rr.cassette_dir`

## `transport.kind = "stdio"`

- `transport.max_line_bytes`

## `transport.kind = "http"`

- `transport.bind_host`
- `transport.bind_port`
- `transport.mcp_path`
- `transport.sse_enabled` (current templates default to `false`)
- `transport.origin_allow_missing`
- `transport.origin_allowlist`
- `transport.session_mode`
- `transport.session_ttl_seconds`
- `transport.session_max`

## Auth and observability

- `auth.mode`: `none` or `oauth2`
- `auth.oauth_config_path`
- `auth.required_scopes`
- `obs.sink`: `stdout_jsonl` or `stderr_jsonl`
- `obs.audit`: boolean
- `obs.metrics`: boolean
