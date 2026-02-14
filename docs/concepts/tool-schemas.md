# Tool schemas

Each tool in `config/mcp.tools.json` includes `inputSchema` (JSON Schema) which is validated and then used to validate the `arguments` object for `tools/call`.

Current validation is a **supported subset** of JSON Schema focused on tool-style object inputs (object/required/properties plus common scalar constraints).

If validation fails, the worker returns an MCP tool error (`isError: true`) with structured diagnostics.
