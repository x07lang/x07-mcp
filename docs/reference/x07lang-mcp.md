# x07lang-mcp

`x07lang-mcp` is the official MCP server for driving the local X07 ecosystem through a token-efficient, file-backed tool surface.

Server repo path:
- `servers/x07lang-mcp/`

Primary install docs:
- [`servers/x07lang-mcp/README.md`](../../servers/x07lang-mcp/README.md)

## Tool groups

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
- Optional wasm/app packs:
  - `x07.wasm.core_v1`
  - `x07.web_ui.exec_v1`
  - `x07.device.exec_v1`
  - `x07.app.exec_v1`
- Service authoring and workload review:
  - `x07.service.init_v1`
  - `x07.service.archetypes_v1`
  - `x07.service.genpack.schema_v1`
  - `x07.service.genpack.grammar_v1`
  - `x07.service.validate_v1`
  - `x07.workload.inspect_v1`
  - `x07.topology.preview_v1`
- Optional platform pack:
  - `lp.query_v1`
  - `lp.control_v1`
  - `lp.release.submit_v1`
  - `lp.release.query_v1`
  - `lp.release.explain_v1`
  - `lp.release.rollback_v1`
  - `lp.binding.status_v1`

## Pack gating

At startup the server detects the local toolchain and writes an effective runtime config plus filtered tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/`.

- core/search/pkg are enabled when `x07` is available
- service authoring is enabled when `x07` is available
- wasm/web-ui/device/app/workload/topology are enabled when `x07-wasm` is available
- `lp.*` release/control/binding tools are enabled when `x07lp` is available

`x07.ecosystem.status_v1` is the cheap probe surface for pack availability, detected helper binaries, and workspace signals.

The official server uses the shipped CLIs as the execution backends for these pack tools, so MCP stays aligned with the canonical command surfaces instead of maintaining a second implementation path.

When you need workspace builds or isolated smoke fixtures, path resolution for the companion CLIs is overridable with:

- `X07_MCP_X07_EXE`
- `X07_MCP_X07_WASM_EXE`
- `X07_MCP_X07LP_EXE`
- `X07_MCP_X07_DEVICE_HOST_DESKTOP_EXE`

## Resources and prompts

The server publishes focused resource entrypoints for the X07 ecosystem:

- `x07://wasm/profiles`
- `x07://web-ui/contracts`
- `x07://device/host-abi`
- `x07://platform/contracts`
- `x07://registry/catalog`
- `x07://agent-portal/index`

Prompts tell agents to probe the environment first, prefer dedicated pack tools over `x07.exec_v1`, and inspect file-backed reports instead of dumping long logs into chat.

## Output model

Exec-style tools return compact structured results with:

- `ok`
- `exit_code`
- `op`
- compact `summary`
- `report_path`
- `artifact_paths`
- optional `incident_bundle_path`

Heavy work is designed to be inspectable through artifacts on disk rather than large inline payloads.
