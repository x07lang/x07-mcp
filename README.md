# x07-mcp

A toolkit for building [MCP](https://modelcontextprotocol.io/) servers in [X07](https://github.com/x07lang/x07) with secure-by-default execution, agent-native contracts, and operational trust.

x07-mcp is designed for **100% agentic coding** — an AI coding agent scaffolds, implements, tests, and publishes an MCP server entirely on its own using the kit's structured contracts and machine-readable outputs. No human needs to write X07 by hand.

## Prerequisites

The [X07 toolchain](https://github.com/x07lang/x07) must be installed before using x07-mcp. If you (or your agent) are new to X07, start with the **[Agent Quickstart](https://x07lang.org/docs/getting-started/agent-quickstart)** — it covers toolchain setup, project structure, and the workflow conventions an agent needs to be productive.

## Use the official X07 MCP server (for coding X07)

If you want an MCP server for writing and repairing X07 programs (instead of building your own MCP server), install the official server: `io.x07/x07lang-mcp`.

- Install the X07 toolchain (the server shells out to the local `x07` CLI).
- Download the published `.mcpb` bundle from the `x07lang-mcp` server README.
- Configure your MCP client to install the `.mcpb`, or unzip it and run `server/x07lang-mcp` with `cwd` set to the extracted bundle root.

Details (release URL, SHA-256, client config notes): `servers/x07lang-mcp/README.md`.

## Why x07-mcp

Most MCP frameworks give you a transport layer and leave security, isolation, and testing as an exercise. x07-mcp ships opinions on all three:

- **Per-tool sandbox isolation.** Each tool runs in its own worker process under an explicit sandbox policy (filesystem allowlists, host allowlists, resource caps). Default-deny, not default-allow.
- **OAuth 2.1 resource-server out of the box.** HTTP servers get RFC 9728 Protected Resource Metadata, audience-bound token validation, DPoP nonce support, and scope-to-tool mapping without writing auth plumbing.
- **Deterministic record/replay testing.** Capture live MCP sessions as JSONL cassettes, replay them in CI with byte-exact golden output, automatic token sanitization.
- **Trust transparency.** TUF-lite anti-rollback, append-only transparency log monitoring, signed publish metadata, and CI gates that fail on capability drift.
- **Agent-native outputs everywhere.** Stable-ordered JSON, structured diagnostics with quickfixes (`x07diag`), machine-readable CLI (`--machine json`). No scraping needed.

## What it includes

| Surface | Description |
|---------|-------------|
| **Library** (`ext-mcp-*`) | Server core, stdio + HTTP transports, OAuth resource-server helpers, schema validation, sandbox/budget wiring, record/replay, trust framework |
| **CLI** (`x07-mcp`) | Scaffold, `dev`, conformance check, `inspect`, `catalog`, bundle `.mcpb`, publish dry-run, trust summaries |
| **Templates** | `mcp-server-stdio`, `mcp-server-http`, `mcp-server-http-tasks` — each with config, replay fixtures, and test harness |
| **Reference servers** | x07lang-mcp, github-mcp, slack-mcp, jira-mcp, postgres-mcp, redis-mcp, s3-mcp, kubernetes-mcp, stripe-mcp, smtp-mcp, http-proxy-mcp |

## Quick start

### Install

Requires X07 toolchain and a C compiler (clang or gcc) on `PATH`.

```sh
x07 bundle --project x07.json --profile os --out dist/x07-mcp
```

Put `dist/x07-mcp` on your `PATH`.

### Scaffold a new server

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-server
```

Templates: `mcp-server-stdio` | `mcp-server-http` | `mcp-server-http-tasks`

### Run (stdio)

```sh
cd my-server
x07 bundle --project x07.json --profile os --out dist/router
x07 bundle --project x07.json --profile os --out dist/worker --entry src/worker_main.x07.json
dist/router
```

### Run (HTTP)

```sh
dist/router            # listens on 127.0.0.1:8314/mcp by default
curl -X POST http://127.0.0.1:8314/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"curl","version":"1"},"capabilities":{}}}'
```

### Run conformance

```sh
x07-mcp conformance --url http://127.0.0.1:8314/mcp --out .x07/artifacts/mcp/conformance/summary.json
```

## For agents

The intended workflow is fully agentic: an AI agent uses the kit to scaffold a server from a template, implement tool handlers, run conformance, and publish — without human intervention. Start with the [Agent Quickstart](https://x07lang.org/docs/getting-started/agent-quickstart) to set up the X07 toolchain, then use the commands below.

All CLI commands support `--machine json` for structured output. Key commands:

```sh
x07-mcp scaffold init --template <T> --dir <D> --machine json
x07-mcp dev --dir <D>
x07-mcp conformance --url <URL> --machine json
x07-mcp inspect tools --url <URL> --machine json
x07-mcp catalog templates --machine json
x07-mcp bundle --mcpb --server-dir <D>
x07-mcp publish --dry-run --machine json
x07-mcp trust summary --machine json
x07-mcp trust tlog-monitor --machine json
```

Diagnostics are emitted as `x07diag` JSON with stable error codes and optional JSON Patch quickfixes.

## Architecture

```
Host (IDE / agent runtime)
  └─ MCP client
       └─ Transport (stdio | HTTP+SSE)
            └─ x07-mcp router
                 ├─ Lifecycle + JSON-RPC dispatch
                 ├─ Auth layer (OAuth 2.1 RS, DPoP, scope mapping)
                 ├─ Feature modules (tools, resources, prompts, logging, completion, tasks)
                 └─ Worker pool
                      └─ Worker process (per-tool sandbox policy + resource caps)
```

The **router** handles transport framing, protocol dispatch, and auth. **Workers** execute tool calls under `run-os-sandboxed` with per-tool policies — filesystem roots, host allowlists, CPU/memory/output caps.

See [Router/worker model](docs/concepts/router-worker.md) and [Sandbox policy](docs/concepts/sandbox.md).

## Documentation

Full docs live in [`docs/`](docs/SUMMARY.md):

- **Getting started:** [Install](docs/getting-started/install.md) · [Scaffold](docs/getting-started/scaffold.md) · [Run stdio](docs/getting-started/run-stdio.md) · [Run HTTP](docs/getting-started/run-http.md) · [Conformance](docs/getting-started/conformance.md) · [Bundle .mcpb](docs/getting-started/bundle-mcpb.md) · [Publish](docs/getting-started/publish.md) · [Trust tlog monitor](docs/getting-started/trust-tlog-monitor.md)
- **Concepts:** [Router/worker](docs/concepts/router-worker.md) · [Tool schemas](docs/concepts/tool-schemas.md) · [Sandbox](docs/concepts/sandbox.md) · [Tasks](docs/concepts/tasks.md) · [Record/replay](docs/concepts/record-replay.md) · [HTTP SSE](docs/concepts/http-sse.md)
- **Reference:** [Server config](docs/reference/server-config.md) · [OAuth config](docs/reference/oauth-config.md) · [Tools manifest](docs/reference/tools-manifest.md) · [Packages](docs/reference/packages.md) · [Pins](docs/reference/pins.md) · [Reference servers](docs/reference/servers.md)

## Protocol

Pinned to MCP protocol version **2025-11-25** (backward-compatible with `2025-06-18` and `2025-03-26`, negotiated at `initialize`).

## Links

- [X07 Agent Quickstart](https://x07lang.org/docs/getting-started/agent-quickstart) — start here
- [X07 toolchain](https://github.com/x07lang/x07)
- [MCP specification](https://modelcontextprotocol.io/specification/2025-11-25)
- [X07 website](https://x07lang.org)

## License

Dual-licensed under [Apache 2.0](LICENSE-APACHE) and [MIT](LICENSE).
