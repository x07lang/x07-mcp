# Server config (`x07.mcp.server_config@0.1.0`)

The server config JSON declares:

- `server.name`, `server.version`, `server.protocolVersion`
- `tools_manifest_path`: path to the tools manifest JSON
- `worker_exe_path`: path to the bundled worker executable
- `transport.kind`: currently `stdio`
- `transport.max_line_bytes`: max inbound line length

The stdio router entry point loads this file and then serves MCP over stdin/stdout.
