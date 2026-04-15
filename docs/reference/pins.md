# MCP Pins

`x07-mcp` pins upstream MCP ecosystem inputs for deterministic CI and release behavior.

- X07 toolchain pin: `x07-toolchain.toml` (`v0.2.3`)
- MCP protocol version: `2025-11-25`
- Registry schema URL: `https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json`
- Registry schema file: `registry/schema/server.schema.2025-12-11.json`
- Conformance runner: `@modelcontextprotocol/conformance@0.1.14`
- MCPB CLI: `@anthropic-ai/mcpb@2.1.2`

Pin source of truth: `arch/pins/mcp_kit.json`.

Local guard: `python3 scripts/ci/check_latest_pins.py` verifies the checked-in MCP pins, the repo-wide X07 toolchain pin, the mirrored workflow env values, and any sibling `x07` workspace checkout. `./scripts/ci/check_all.sh` runs it automatically.
