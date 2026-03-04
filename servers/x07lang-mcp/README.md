# x07lang-mcp

Official MCP server for the X07 language: deterministic, token-efficient, and secure-by-default (network disabled by default).

## Tools
- `x07.search_v1`
- `x07.resource_snippet_v1`
- `x07.doc_v1`
- `x07.cli.describe_v1`
- `x07.patch_apply_v1`
- `x07.fmt_write_v1`
- `x07.lint_report_v1`
- `x07.context_pack_v1`
- `x07.exec_v1`
- `x07.artifact_snippet_v1`

## Run
- Stdio (default): `x07 run`
- HTTP (no-auth dev): `X07_MCP_CFG_PATH=config/mcp.server.dev.json x07 run`
- HTTP (oauth): `X07_MCP_CFG_PATH=config/mcp.server.http.oauth.json x07 run`

## Test
- `x07 test --manifest tests/tests.json`

## Build `.mcpb`
- `./publish/build_mcpb.sh`
