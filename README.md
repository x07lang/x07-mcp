# x07-mcp

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/x07lang/x07-mcp?quickstart=1)

Official MCP kit for X07, plus the official `io.x07/x07lang-mcp` server.

This repo is the bridge between the X07 toolchain and MCP runtimes. It gives you the packages, CLI, templates, docs, and reference servers needed to build MCP servers in X07, and it also ships the official server that coding agents use to work on X07 projects.

**Start here:** [Codespaces quickstart](docs/getting-started/codespaces.md) · [Scaffold guide](docs/getting-started/scaffold.md) · [Official server README](servers/x07lang-mcp/README.md) · [Postgres demo](demos/postgres-public-beta/README.md) · [X07 Agent Quickstart](https://x07lang.org/docs/getting-started/agent-quickstart)

## Choose Your Path

### Use the official X07 MCP server

If you want an MCP server for writing, inspecting, testing, and operating X07 projects, use the published `io.x07/x07lang-mcp` server from this repo.

1. Install the X07 toolchain.
2. Download the published `.mcpb` bundle described in [`servers/x07lang-mcp/README.md`](servers/x07lang-mcp/README.md).
3. Configure your MCP client to install or run that bundle.

The server uses your local `x07` toolchain and exposes structured tooling for editing X07 code, querying packages, running WASM/device/app operations, and working with selected platform surfaces.

### Build an MCP server in X07

If you want to ship your own MCP server, this repo gives you the kit, scaffolds, and publish flow.

Fastest path:

```bash
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-server
cd my-server
x07 bundle --project x07.json --profile os --out dist/router
x07 bundle --project x07.json --profile os --out dist/worker --entry src/worker_main.x07.json
dist/router
```

Preferred starting points:

- `docs/getting-started/codespaces.md` for zero-install exploration
- `docs/getting-started/scaffold.md` for local scaffolding
- `docs/getting-started/run-stdio.md` and `docs/getting-started/run-http.md` for transport-specific flows

### Verify an MCP server

If you want to verify any MCP server, including one not built in X07, use [Hardproof](https://github.com/x07lang/hardproof).

```bash
hardproof scan --url "http://127.0.0.1:3000/mcp" --out out/scan --format rich
```

If you do not provide trust inputs (`--server-json` and, when available, `--mcpb`), Hardproof may produce a partial score instead of a publishable full score.

## What This Repo Includes

- `ext-mcp-*` packages for server core, transports, auth, sandboxing, replay, trust, and publish flows
- `x07-mcp` CLI for scaffolding, conformance, inspection, bundling, publish readiness, and trust tooling
- templates: `mcp-server-stdio`, `mcp-server-http`, and `mcp-server-http-tasks`
- the official `io.x07/x07lang-mcp` server
- reference servers for GitHub, Postgres, Redis, S3, Kubernetes, Slack, Jira, Stripe, SMTP, and more
- a public Postgres demo path under `demos/postgres-public-beta/`

## Why x07-mcp

- **Secure-by-default execution.** Tool calls run through explicit router and worker boundaries with sandbox policy and resource caps.
- **Built-in auth story.** HTTP servers get OAuth 2.1 resource-server support, Protected Resource Metadata, DPoP nonce handling, and scope-to-tool mapping.
- **Deterministic replay.** Record and replay flows make regressions and CI failures reproducible.
- **Trust-aware publish flow.** Bundles, registry metadata, and transparency checks are first-class parts of the kit.
- **Agent-native outputs.** CLI commands support machine-readable output so agents can operate on contracts instead of scraping logs.

## How It Fits The X07 Ecosystem

- [`x07`](https://github.com/x07lang/x07) provides the language, repair loop, package manager, and core docs
- `x07-mcp` provides the MCP-facing packages, templates, conformance flow, and official X07 MCP server
- [`hardproof`](https://github.com/x07lang/hardproof) verifies MCP servers and release artifacts across language boundaries
- [`x07-wasm-backend`](https://github.com/x07lang/x07-wasm-backend), [`x07-web-ui`](https://github.com/x07lang/x07-web-ui), [`x07-device-host`](https://github.com/x07lang/x07-device-host), and [`x07-platform`](https://github.com/x07lang/x07-platform) provide downstream capability surfaces that agents can reach through structured tool contracts

## Architecture

```text
Host (IDE / agent runtime)
  -> MCP client
    -> Transport (stdio | HTTP + SSE)
      -> x07-mcp router
        -> protocol dispatch, auth, lifecycle, tools/resources/prompts
        -> worker pool
          -> per-tool worker process with sandbox policy and resource caps
```

The router owns transport framing, protocol dispatch, and auth. Workers execute tool calls under explicit policy instead of letting every tool share unrestricted process state.

See [`docs/concepts/router-worker.md`](docs/concepts/router-worker.md) and [`docs/concepts/sandbox.md`](docs/concepts/sandbox.md).

## Docs And Examples

Key docs:

- getting started: [`docs/getting-started/`](docs/getting-started/)
- concepts: [`docs/concepts/`](docs/concepts/)
- reference: [`docs/reference/`](docs/reference/)
- reference servers: [`docs/reference/servers.md`](docs/reference/servers.md)

Public example flows:

- [`demos/postgres-public-beta/README.md`](demos/postgres-public-beta/README.md) for the hero demo path
- [`docs/examples/trusted_program_sandboxed_local_stdio_v1/`](docs/examples/trusted_program_sandboxed_local_stdio_v1/)
- [`docs/examples/trusted_program_sandboxed_net_http_v1/`](docs/examples/trusted_program_sandboxed_net_http_v1/)
- [`docs/examples/verified_core_pure_auth_core_v1/`](docs/examples/verified_core_pure_auth_core_v1/)

## Agent-Facing Outputs

All major CLI commands support `--machine json`.

Two builder-facing outputs are especially useful for automation:

- `x07-mcp bundle --mcpb --server-dir <DIR> --machine json` emits `x07.mcp.bundle.summary@0.1.0`
- `x07-mcp publish --dry-run --server-json <SERVER_JSON> --mcpb <MCPB> --machine json` emits `x07.mcp.publish.readiness@0.1.0`

Those documents carry stable artifact references, transport and capability summaries, trust/readiness status, and explicit blockers or warnings.

## Validation

Repo gate:

```bash
./scripts/ci/check_all.sh
```

For CI-parity lock and smoke checks:

```bash
X07_MCP_LOCAL_DEPS=1 X07_MCP_LOCAL_DEPS_REFRESH=1 X07_MCP_SKIP_STDIO_SMOKE=1 ./scripts/ci/check_all.sh
```

If you keep a sibling `../x07` checkout, it must be a clean checkout of the exact pinned tag from `x07-toolchain.toml`, or you must point `X07_ROOT` at a matching worktree.

## Protocol

Pinned to MCP protocol version `2025-11-25`, with backward-compatible negotiation for `2025-06-18` and `2025-03-26`.

## License

Dual-licensed under [Apache 2.0](LICENSE-APACHE) and [MIT](LICENSE).
