# x07lang-mcp

Official MCP server for the X07 language: `io.x07/x07lang-mcp`.

Designed for agentic X07 coding loops: search docs/skills, run the toolchain, apply JSON Patch safely, and return token-efficient context packs — with per-tool sandboxing (network disabled by default).

## Install (published `.mcpb`)

Prerequisites:
- Install the X07 toolchain (the server uses the local `x07` CLI for `x07.exec_v1`).
- Ensure you have an absolute path to `x07` (no PATH search in `execve`): `command -v x07`.

Download:
- GitHub release: `x07lang-mcp-v0.2.3`
- `.mcpb` URL: https://github.com/x07lang/x07-mcp/releases/download/x07lang-mcp-v0.2.3/x07lang-mcp.mcpb
- `.mcpb` SHA-256: `d61fb7eadf1772a576c393871b112a2b6dfba6dde7ad6f35422aabde5e2bfdfb`

Verify (macOS / Linux):

```bash
got="$(shasum -a 256 x07lang-mcp.mcpb | awk '{print $1}')"
test "$got" = "d61fb7eadf1772a576c393871b112a2b6dfba6dde7ad6f35422aabde5e2bfdfb"
```

Configure your MCP client:
- If your client supports `.mcpb`, install the bundle.
- If your client requires a `command`/`args` server definition, extract the bundle and run the router binary from the bundle root:

  ```bash
  unzip -q x07lang-mcp.mcpb -d x07lang-mcp.bundle
  ```

  Use:
  - `command`: `.../x07lang-mcp.bundle/server/x07lang-mcp`
  - `cwd`: `.../x07lang-mcp.bundle` (so `config/mcp.server.json` + `out/mcp-worker` resolve)
  - env (recommended): `X07_MCP_X07_EXE=/absolute/path/to/x07`

## Tools
- Core:
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
- Discovery:
  - `x07.ecosystem.status_v1`
  - `x07.pkg.provides_v1`
  - `x07.pkg.catalog_v1`
- Optional packs:
  - `x07.wasm.core_v1`
  - `x07.web_ui.exec_v1`
  - `x07.device.exec_v1`
  - `x07.app.exec_v1`
  - `lp.query_v1`
  - `lp.control_v1`

`x07lang-mcp` writes an effective runtime server config plus filtered tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/`. The advertised surface is gated by the installed toolchain:

- core/search/pkg when `x07` is available
- wasm/web-ui/device/app when `x07-wasm` is available
- `lp.*` when `x07lp` is available

Dedicated pack tools return bounded summaries with file-backed reports and artifacts. Use `x07.artifact_snippet_v1` or resource reads to inspect the full output only when needed.

## Run (from source)

Build router + worker binaries:
- Binaries only: `X07_MCP_BUILD_BINS_ONLY=1 ./publish/build_mcpb.sh`
- Or build `.mcpb` (also builds binaries): `./publish/build_mcpb.sh`

`./publish/build_mcpb.sh` always rebuilds the router and worker binaries before packing, then refreshes `dist/server.json` from `x07.mcp.json` against the newly built bundle.

Run:
- Stdio (default): `X07_MCP_CFG_PATH=config/mcp.server.json out/x07lang-mcp`
- HTTP (no-auth dev): `X07_MCP_CFG_PATH=config/mcp.server.dev.json out/x07lang-mcp`
- HTTP (oauth): `X07_MCP_CFG_PATH=config/mcp.server.http.oauth.json out/x07lang-mcp`

## Test
- `x07 test --manifest tests/tests.json`
- stdio smoke: `python3 tests/stdio_smoke.py`
- published bundle smoke: `python3 tests/published_bundle_smoke.py`
- package lock refresh: `x07 pkg lock --project x07.json`

## Build `.mcpb`
- `./publish/build_mcpb.sh`
