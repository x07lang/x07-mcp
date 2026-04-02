# Flagship demo: Postgres (public beta)

The Postgres demo is the end-to-end “hero path” for the MCP public beta:

1. start one real MCP server,
2. run `x07-mcp-test` conformance + replay checks against it, and
3. verify release-grade metadata (`server.json` trust metadata + `.mcpb` bundle consistency).

The canonical command sequence lives in `demos/postgres-public-beta/README.md`.

## Prerequisites

- X07 toolchain installed (`x07`)
- `x07-mcp-test` installed on `PATH` (or installed via `./scripts/dev/install_x07_mcp_test.sh`)
- Docker + Docker Compose (for the local Postgres dependency)

## Run the demo locally

From the repo root:

```sh
cd demos/postgres-public-beta
./scripts/run_demo.sh --deps-only
```

In one terminal, build + run the server:

```sh
./scripts/run_demo.sh --server
```

In another terminal, run verifier commands and produce artifacts:

```sh
./scripts/verify_demo.sh
```

Optionally, capture a copy of outputs + a command log for docs/website work:

```sh
./scripts/capture_outputs.sh
```

## Expected artifacts

Under `demos/postgres-public-beta/out/`:

- `conformance/summary.json`
- `conformance/summary.junit.xml`
- `conformance/summary.html`
- `conformance/summary.sarif.json`
- `replay.session.json`
- `replay-verify/verify.json`
- `trust.summary.json`
- `bundle.verify.json`

## Notes

- The server listens on `http://127.0.0.1:8403/mcp`.
- Trust and bundle verification use the generated release-like artifacts under `servers/postgres-mcp/dist/`.
