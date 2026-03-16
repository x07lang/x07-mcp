# x07-mcp

`x07-mcp` is the official MCP kit for [X07](https://github.com/x07lang/x07). It gives you the library code, CLI, templates, docs, and reference servers needed to build Model Context Protocol servers in X07 with secure-by-default execution and machine-readable contracts.

The vision is to make MCP servers feel like first-class x07 applications: deterministic where they should be deterministic, explicit about trust and sandbox boundaries, and simple enough for end users and coding agents to operate without hand-built framework glue.

x07-mcp is designed for **100% agentic coding**. An AI coding agent can scaffold, implement, test, inspect, bundle, and publish an MCP server using structured outputs instead of brittle log scraping or custom shell scripts.

## How it fits into the x07 ecosystem

`x07-mcp` plays two roles in the larger x07 story:

- It is the **toolkit repo** for people building their own MCP servers in X07.
- It is also the home of the **official `x07lang-mcp` server**, which coding agents use to work with x07 projects and selected ecosystem surfaces.

That makes it one of the bridges between the x07 language and real agent runtimes:

- **`x07`** provides the language, repair loop, package manager, and core docs.
- **`x07-mcp`** provides the MCP-facing packaging, templates, conformance flow, and the official x07 MCP server.
- **`x07-wasm-backend`**, **`x07-web-ui`**, **`x07-device-host`**, and **`x07-platform`** expose capabilities that the official server and future MCP apps can use through structured tool contracts.

If you want an agent to write x07 well, you usually consume the official server from this repo. If you want to build your own MCP product in x07, this repo is your starting point.

## Prerequisites

The [X07 toolchain](https://github.com/x07lang/x07) must be installed before using x07-mcp. If you (or your agent) are new to X07, start with the **[Agent Quickstart](https://x07lang.org/docs/getting-started/agent-quickstart)** — it covers toolchain setup, project structure, and the workflow conventions an agent needs to be productive.

## Practical usage

Common ways people use this repo:

- **Run the official x07 MCP server** so an IDE or coding agent can inspect and edit x07 projects through MCP.
- **Scaffold a new MCP server** from a template and implement tool handlers in X07.
- **Bundle and publish** an `.mcpb` package with reproducible metadata and trust checks.
- **Run conformance and replay tests** before release.

## Formal verification dogfood

`x07-mcp` publishes the current formal-verification story directly in this repo
instead of burying the contract line and certification design in internal docs.
The public examples now track the current schema line
(`x07.x07ast@0.8.0`, `x07.project@0.4.0`, `x07.trust.profile@0.4.0`,
`x07.trust.certificate@0.6.0`) and make the certification posture explicit:

- `docs/examples/trusted_program_sandboxed_local_stdio_v1/`
  - canonical strong-profile example
  - certifies the operational server entry `router.main_v1`
  - binds the shipped stdio router and worker through checked capsule
    attestations plus runtime-attestation evidence, and rejects the old
    `certify.main_v1` surrogate helper path
- `docs/examples/trusted_program_sandboxed_net_http_v1/`
  - developer/demo network example built from the HTTP router/worker template
  - keeps the same operational entry split, but is not the release-gated strong
    certification path yet
- `docs/examples/verified_core_pure_auth_core_v1/`
  - developer/demo verified-core example around the published
    `ext-mcp-auth-core` package
  - demonstrates the imported-stub developer flow and the expected strong
    rejection when prove mode refuses that bearer-parser path

The public design is intentional:

- `router.main_v1` is the operational entry that a strong certificate must
  cover.
- `certify.main_v1` remains only as a local developer helper for smoke flows and
  surrogate-rejection tests.
- proof summaries support review, but strong evidence can come from either
  checked proof objects or checked certified-capsule attestations depending on
  the trust zone of the reachable operational surface.

Use the example READMEs for the full command sequences. The short form is:

```sh
cd docs/examples/verified_core_pure_auth_core_v1
x07 pkg lock --project x07.json
x07 test --all --manifest tests/tests.json
x07 verify --project x07.json --entry auth_core_cert.main_v1 --prove
x07 verify --project x07.json --entry auth_core_cert.main_v1 --prove --allow-imported-stubs --emit-proof target/auth_core.proof.json
x07 prove check --proof target/auth_core.proof.json
x07 trust certify --project x07.json --profile arch/trust/profiles/verified_core_pure_v1.json --entry auth_core_cert.main_v1 --out-dir target/cert
```

The first prove command is expected to fail with `X07V_IMPORTED_STUB_FORBIDDEN`.
The last command is expected to reject the strong claim for the same reason.

For the release-gated stdio example, use:

```sh
cd docs/examples/trusted_program_sandboxed_local_stdio_v1
x07 pkg lock --project x07.json
x07 trust profile check --project x07.json --profile arch/trust/profiles/trusted_program_sandboxed_local_v1.json --entry router.main_v1
x07 test --all --manifest tests/tests.json
x07 trust capsule check --project x07.json --index arch/capsules/index.x07capsule.json
python3 tests/stdio_bundle_smoke.py
x07 trust certify --project x07.json --profile arch/trust/profiles/trusted_program_sandboxed_local_v1.json --entry router.main_v1 --out-dir target/cert
```

This example is the capsule-backed strong-profile path, so the accepted
certificate may legitimately carry zero proof objects when the operational entry
terminates at certified capsule boundaries.

For the network example, run the same package lock, tests, capsule check, and
profile check against `router.main_v1`, but treat it as a developer example
rather than the repo's golden strong-profile path.

## Use the official X07 MCP server (for coding X07)

If you want an MCP server for writing and repairing X07 programs (instead of building your own MCP server), install the official server: `io.x07/x07lang-mcp`.

- Install the X07 toolchain (the server shells out to the local `x07` CLI).
- Download the published `.mcpb` bundle from the `x07lang-mcp` server README.
- Configure your MCP client to install the `.mcpb`, or unzip it and run `server/x07lang-mcp` with `cwd` set to the extracted bundle root.

Details (release URL, SHA-256, client config notes): `servers/x07lang-mcp/README.md`.

The official server now exposes the public certification workflow directly to
agents through `x07://trust/formal-verification`, `x07.doc_v1`, and
`x07.exec_v1`, so the proof/certificate flow is discoverable without opening
internal development notes.

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

Requires the X07 toolchain and a C compiler (`clang` or `gcc`) on `PATH`.

```sh
x07 bundle --project x07.json --profile os --out dist/x07-mcp
```

Put `dist/x07-mcp` on your `PATH`.

### Scaffold a new server

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-server
```

Templates: `mcp-server-stdio` | `mcp-server-http` | `mcp-server-http-tasks`

When you are working from the main x07 toolchain entrypoint, prefer the published x07 template flow for end-user projects and then use this repo when you need the underlying kit, template source, or reference servers.

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
x07-mcp bundle --mcpb --server-dir <D> --machine json
x07-mcp publish --dry-run --machine json
x07-mcp trust summary --machine json
x07-mcp trust tlog-monitor --machine json
```

Forge M4 relies on two builder-grade machine outputs:

- `x07-mcp bundle --mcpb --server-dir <D> --machine json` emits `x07.mcp.bundle.summary@0.1.0`
- `x07-mcp publish --dry-run --server-json <S> --mcpb <B> --machine json` emits `x07.mcp.publish.readiness@0.1.0`

Those documents include transport and capability summaries, trust/readiness status, explicit blockers and warnings, and stable artifact references so UI consumers can render publish-readiness directly without scraping human text.

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
