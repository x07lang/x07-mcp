# x07lang-mcp

Official MCP server for the X07 language: `io.x07/x07lang-mcp`.

Designed for agentic X07 coding loops: search docs/skills, run the toolchain, apply JSON Patch safely, and return token-efficient context packs, with per-tool sandboxing and the public formal-verification/certification docs surfaced directly to the client.

## Install (published `.mcpb`)

Prerequisites:
- Install the X07 toolchain (the server uses the local `x07` CLI for `x07.exec_v1`).
- Ensure you have an absolute path to `x07` (no PATH search in `execve`): `command -v x07`.

Download:
- GitHub release: `x07lang-mcp-v0.2.6`
- `.mcpb` URL: https://github.com/x07lang/x07-mcp/releases/download/x07lang-mcp-v0.2.6/x07lang-mcp.mcpb
- `.mcpb` SHA-256: `294d4663e29a9ff3c1cb3d150e27e631fcde356146392ba1939a6b0b328688a4`

Verify (macOS / Linux):

```bash
got="$(shasum -a 256 x07lang-mcp.mcpb | awk '{print $1}')"
test "$got" = "294d4663e29a9ff3c1cb3d150e27e631fcde356146392ba1939a6b0b328688a4"
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
  - optional helper overrides:
    - `X07_MCP_X07_WASM_EXE=/absolute/path/to/x07-wasm`
    - `X07_MCP_X07LP_EXE=/absolute/path/to/x07lp`
    - `X07_MCP_X07_DEVICE_HOST_DESKTOP_EXE=/absolute/path/to/x07-device-host-desktop`

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
  - `x07.service.init_v1`
  - `x07.service.archetypes_v1`
  - `x07.service.genpack.schema_v1`
  - `x07.service.genpack.grammar_v1`
  - `x07.service.validate_v1`
  - `x07.workload.inspect_v1`
  - `x07.topology.preview_v1`
  - `lp.query_v1`
  - `lp.control_v1`
  - `lp.release.submit_v1`
  - `lp.release.query_v1`
  - `lp.release.explain_v1`
  - `lp.release.rollback_v1`
  - `lp.binding.status_v1`

`x07lang-mcp` writes an effective runtime server config plus filtered tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/`. The advertised surface is gated by the installed toolchain:

- core/search/pkg when `x07` is available
- service authoring when `x07` is available
- wasm/web-ui/device/app/workload/topology when `x07-wasm` is available
- `lp.*` release, control, and binding tools when `x07lp` is available

The service/workload/Sentinel additions keep the same rule as the older pack surfaces: the MCP server shells out to the canonical CLIs instead of carrying a parallel implementation, so CLI behavior and MCP behavior stay aligned.

Typical hosted PaaS loop through the official server:

- scaffold and validate with `x07.service.init_v1`, `x07.service.genpack.*`, and `x07.service.validate_v1`
- review the bounded workload shape with `x07.workload.inspect_v1` and `x07.topology.preview_v1`
- submit and review a hosted release with `lp.release.submit_v1`, `lp.release.query_v1`, `lp.release.explain_v1`, `lp.release.rollback_v1`, and `lp.binding.status_v1`

Dedicated pack tools return bounded summaries with file-backed reports and artifacts. Use `x07.artifact_snippet_v1` or resource reads to inspect the full output only when needed.

Formal verification and certification are exposed through the existing core surface rather than a separate special-case tool:

- `x07://trust/formal-verification` points agents at the public docs, examples, and command sequence.
- `x07.doc_v1` and `x07.search_v1` discover the docs/examples.
- `x07.exec_v1` runs `x07 verify --prove`, `x07 trust profile check`, `x07 pkg attest-closure`, `x07 trust capsule check`, and `x07 trust certify`.

That keeps the server surface small while making the certification workflow explicit for end users and coding agents.

## Run (from source)

The current source tree tracks the Milestone C `x07.x07ast@0.8.0` line. For
local source builds, use a matching `x07` binary, preferably a workspace build
such as `../x07/target/debug/x07` via `X07_MCP_X07_EXE=/absolute/path/to/x07`.
The published `.mcpb` above remains the last released bundle.

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
