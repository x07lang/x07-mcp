# Tools manifest (`x07.mcp.tools_manifest@0.1.0`)

The tools manifest JSON declares a fixed set of tools and their execution metadata.

Each entry in `tools[]` includes:

- `name`: MCP tool name
- `description` (optional)
- `inputSchema`: JSON Schema describing `tools/call.params.arguments`
- `x07.impl`: an implementation reference (string)
- `x07.sandbox` (optional): allowlists for filesystem/network/env
- `x07.limits_profile` (optional): selects a caps profile for worker execution

Tool names must match MCP constraints (1–128 chars; `A-Z a-z 0-9 _ - .`).
