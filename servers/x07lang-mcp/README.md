# x07lang-mcp

Official MCP server for the X07 language: `io.x07/x07lang-mcp`.

X07 is the deterministic, certifiable execution substrate for agent-written software, and this server is how coding agents drive it over MCP. Designed for agentic X07 coding loops: search docs/skills, run the toolchain, apply JSON Patch safely, and return token-efficient context packs, with per-tool sandboxing and the public formal-verification/certification docs surfaced directly to the client.

## Install (published `.mcpb`)

Prerequisites:
- Install the X07 toolchain. The server uses the local `x07` CLI for `x07.exec_v1`, `x07.fmt_write_v1`, and the other tool-backed helpers.
- Optional but useful: confirm the binary you want is visible via `command -v x07`.

Download:
- GitHub release: `x07lang-mcp-v0.2.10`
- `.mcpb` URL: https://github.com/x07lang/x07-mcp/releases/download/x07lang-mcp-v0.2.10/x07lang-mcp.mcpb
- `.mcpb` SHA-256: `a3bce917985fca5ae0d5d86dc1cafbbeb621d9cbcdb077ad67050174fec83b84`

Verify (macOS / Linux):

```bash
got="$(shasum -a 256 x07lang-mcp.mcpb | awk '{print $1}')"
test "$got" = "a3bce917985fca5ae0d5d86dc1cafbbeb621d9cbcdb077ad67050174fec83b84"
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
  - `x07` resolution order:
    - explicit override: `X07_MCP_X07_EXE=/absolute/path/to/x07`
    - executable probe across `PATH`, while skipping a stale `~/.x07/bin` shadow when a better `x07` is already present earlier on `PATH`
    - standard install paths: `/opt/homebrew/bin/x07`, `/usr/local/bin/x07`, `/usr/bin/x07`
    - fallback: `~/.x07/bin/x07`
  - candidate paths are accepted only if the server can actually spawn them; a stale shim or a shell-only alias is ignored
  - env override (recommended when you want to pin one specific toolchain build): `X07_MCP_X07_EXE=/absolute/path/to/x07`
  - optional helper overrides:
    - `X07_MCP_X07_WASM_EXE=/absolute/path/to/x07-wasm`

### Install for Claude Code

`scripts/install_local.sh` downloads the released bundle for a tag, verifies its
SHA-256 against the published `.sha256.txt`, extracts it under
`~/.local/share/x07lang-mcp/releases/<tag>/bundle`, atomically repoints the
`~/.local/share/x07lang-mcp/current` symlink, and creates the
`~/.local/share/x07lang-mcp/bin/x07lang-mcp-stdio` wrapper:

```bash
./scripts/install_local.sh                            # tag from x07.mcp.json version
./scripts/install_local.sh --tag x07lang-mcp-v0.2.10  # explicit release tag
./scripts/install_local.sh --mcpb dist/x07lang-mcp.mcpb  # install a local bundle
```

Then register the server with Claude Code:

```bash
claude mcp add x07lang-mcp -s user -- "$HOME/.local/share/x07lang-mcp/bin/x07lang-mcp-stdio"
```

The wrapper runs the bundled router from the install root and defaults
`X07_MCP_X07_EXE` to `~/.x07/bin/x07`; export `X07_MCP_X07_EXE` before launch to
pin a different toolchain build. `./scripts/install_local.sh --uninstall`
removes `~/.local/share/x07lang-mcp`.

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
  - `x07.pkg.tree_v1`
  - `x07.pkg.verify_v1`
  - `x07.pkg.check_semver_v1`
  - `x07.pkg.provides_v1`
  - `x07.pkg.catalog_v1`
- Optional packs:
  - `x07.wasm.core_v1`
  - `x07.service.init_v1`
  - `x07.service.archetypes_v1`
  - `x07.service.genpack.schema_v1`
  - `x07.service.genpack.grammar_v1`
  - `x07.service.validate_v1`
  - `x07.workload.inspect_v1`
  - `x07.topology.preview_v1`

Removed packs (2026-06 refocus): the `x07.web_ui.*`, `x07.device.*`, `x07.app.*`, and `lp.*` tools were removed from this server when their backing repos (`x07-web-ui`, `x07-device-host`, and the `x07-platform*` control plane) were archived and made read-only on GitHub.

Toolchain feature notes:

- `x07.doc_v1` returns `x07 doc` output; on x07 0.2.11+ export rows also carry an optional behavioral `summary` field (one-line contracts covering separators, encodings, error codes, and move semantics).
- The lossless x07text projection (`x07 ast to-text` / `x07 ast from-text`, x07 0.2.11+) is available through `x07.exec_v1` until a dedicated tool ships; both subcommands emit `{ok,in,out,sha256}` reports, and `from-text` output is byte-identical to `x07 fmt` canonical bytes.

`x07lang-mcp` writes an effective runtime server config plus filtered tools/resources/prompts manifests under `.x07/artifacts/mcp/runtime/`. The advertised surface is gated by the installed toolchain:

- core/search/pkg when `x07` is available
- service authoring when `x07` is available
- wasm/workload/topology when `x07-wasm` is available

The service/workload additions keep the same rule as the older pack surfaces: the MCP server shells out to the canonical CLIs instead of carrying a parallel implementation, so CLI behavior and MCP behavior stay aligned.

Typical service authoring loop through the official server:

- scaffold and validate with `x07.service.init_v1`, `x07.service.genpack.*`, and `x07.service.validate_v1`
- review the bounded workload shape with `x07.workload.inspect_v1` and `x07.topology.preview_v1`

Dedicated pack tools return bounded summaries with file-backed reports and artifacts. Use `x07.artifact_snippet_v1` or resource reads to inspect the full output only when needed.

Formal verification and certification are exposed through the existing core surface rather than a separate special-case tool:

- `x07://trust/formal-verification` points agents at the public docs, examples, and command sequence.
- `x07.doc_v1` and `x07.search_v1` discover the docs/examples.
- `x07.exec_v1` runs `x07 verify --prove`, `x07 trust profile check`, `x07 pkg attest-closure`, `x07 trust capsule check`, and `x07 trust certify`.

That keeps the server surface small while making the certification workflow explicit for end users and coding agents.

## Run (from source)

The source tree tracks the `x07.x07ast@0.8.0` line and builds with the
repo-pinned toolchain from `x07-toolchain.toml`. To pin a specific build,
set `X07_MCP_X07_EXE=/absolute/path/to/x07`. If you keep a sibling `../x07`
checkout, local checks require it to be a clean checkout of the exact pinned
tag, or `X07_ROOT` must point at a matching worktree.

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
  - covers the extracted install layout and validates tool resolution against an actually spawnable `x07` binary
- package lock refresh: `x07 pkg lock --project x07.json`

## Build `.mcpb`
- `./publish/build_mcpb.sh`
