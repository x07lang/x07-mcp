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
- Optional wasm pack:
  - `x07.wasm.core_v1`
- Service authoring and workload review:
  - `x07.service.init_v1`
  - `x07.service.archetypes_v1`
  - `x07.service.genpack.schema_v1`
  - `x07.service.genpack.grammar_v1`
  - `x07.service.validate_v1`
  - `x07.workload.inspect_v1`
  - `x07.topology.preview_v1`

## Removed packs

The `x07.web_ui.*`, `x07.device.*`, `x07.app.*`, and `lp.*` tool packs were removed from this server in the 2026-06 refocus, when the `x07-web-ui`, `x07-device-host`, and `x07-platform*` repos were archived.

## Pack gating

At startup the server detects the local toolchain and writes an effective runtime config plus filtered tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/`.

- core/search/pkg are enabled when `x07` is available
- service authoring is enabled when `x07` is available
- wasm/workload/topology are enabled when `x07-wasm` is available

`x07.ecosystem.status_v1` is the cheap probe surface for pack availability, detected helper binaries, and workspace signals.

The official server uses the shipped CLIs as the execution backends for these pack tools, so MCP stays aligned with the canonical command surfaces instead of maintaining a second implementation path.

When you need workspace builds or isolated smoke fixtures, path resolution for the companion CLIs is overridable with:

- `X07_MCP_X07_EXE`
- `X07_MCP_X07_WASM_EXE`

## Toolchain feature notes

- `x07.doc_v1` passes through `x07 doc` output; on x07 0.2.11+ export rows also carry an optional behavioral `summary` field with one-line contracts (separators, encodings, error codes, move semantics).
- The lossless x07text projection (`x07 ast to-text` / `x07 ast from-text`, x07 0.2.11+) is available through `x07.exec_v1` until a dedicated tool ships. Both subcommands emit `{ok,in,out,sha256}` reports, and `from-text` output is byte-identical to `x07 fmt` canonical bytes.

## Resources and prompts

The server publishes focused resource entrypoints for the X07 ecosystem:

- `x07://wasm/profiles`
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
