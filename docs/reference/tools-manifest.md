# Tools manifest (`x07.mcp.tools_manifest@0.2.0`)

The tools manifest JSON declares the server’s tools and execution metadata.

Each entry in `tools[]` includes:

- `name`: MCP tool name
- `description` (optional)
- `inputSchema`: JSON Schema for `tools/call.params.arguments`
- `annotations` (optional): passthrough metadata for `tools/list`
- `auth.required_scopes` (optional): per-tool OAuth scopes
- `x07.impl`: implementation symbol string
- `x07.sandbox` (optional): filesystem/network/env allowlists
- `x07.limits_profile` (optional): budget + caps profile

Tool names follow MCP constraints (1–128 chars; `A-Z a-z 0-9 _ - .`).
