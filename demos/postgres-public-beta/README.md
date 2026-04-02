# Postgres public-beta demo

This directory defines the public hero demo path and the verifier command sequence.

## Environment contract

This demo assumes:

- You are in the `x07lang/x07-mcp` repo.
- The X07 toolchain is installed (the demo uses `x07 bundle` and runs native bundles).
- `x07-mcp-test` is installed on `PATH` (or installed via `./scripts/dev/install_x07_mcp_test.sh`).
- A Postgres instance is reachable with a known DSN (this demo uses Docker Compose by default).
- The MCP server runs over Streamable HTTP at `http://127.0.0.1:8403/mcp`.

## Demo flow (frozen sequence)

### 1) Start Postgres

From this directory:

```sh
./scripts/run_demo.sh --deps-only
```

### 2) Build + run the Postgres MCP server

In one terminal:

```sh
./scripts/run_demo.sh --server
```

Expected:
- server listens on `http://127.0.0.1:8403/mcp`

### 3) Verify the server with `x07-mcp-test`

In another terminal:

```sh
./scripts/verify_demo.sh
```

Expected artifacts under `demos/postgres-public-beta/out/`:
- `conformance/summary.json`
- `conformance/summary.junit.xml`
- `conformance/summary.html`
- `conformance/summary.sarif.json`
- `replay.session.json`
- `replay-verify/verify.json`
- `trust.summary.json`
- `bundle.verify.json`

### 4) Capture outputs for website/content work

```sh
./scripts/capture_outputs.sh
```

This copies the verifier outputs plus a command log into `demos/postgres-public-beta/out/captured/`.
