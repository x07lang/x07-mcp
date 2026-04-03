# MCP Conformance Harness

This directory contains conformance harnesses for x07-mcp:

- **Server mode**: Hardproof (`hardproof scan`) against an x07-mcp Streamable HTTP server (no Node.js required).
- **Client mode**: upstream MCP conformance client suite, using `conformance/client-x07/` for the auth suite.
- **Trust tlog mode**: deterministic monitor scenarios via `conformance/trust-tlog/`.

Hardproof and the upstream conformance runner both support an **expected failures** file;
failures not listed there fail the run, and "expected failures" that stop failing also fail
the run (stale baseline).

## Pinned tool versions

- `@modelcontextprotocol/conformance@0.1.14`

## Quickstart (local)

1) Run Hardproof against an already running server:

   `hardproof scan --url http://127.0.0.1:8080/mcp --out out/conformance --machine json`

2) Or let the harness spawn a server and run Hardproof:

   `./conformance/run_server_conformance.sh --spawn postgres-mcp --mode noauth --results-dir out/conformance-postgres-mcp`

3) Client mode (auth suite):

   `x07 bundle --project conformance/client-x07/x07.json --profile os --out dist/x07-mcp-conformance-client`

   `npx -y @modelcontextprotocol/conformance@0.1.14 client --command "./dist/x07-mcp-conformance-client" --suite auth`

4) Trust tlog monitor scenarios:

   `./conformance/trust-tlog/run.sh`

## Baseline policy

- Keep `conformance-baseline.yml` tiny.
- Delete entries as soon as the feature lands.
- Never baseline a real regression.

## CI usage pattern

- Start server in background
- Wait for port to respond (any status other than 000 is "up")
- Run conformance with `--baseline conformance-baseline.yml`
- Store `results/**` as an artifact
