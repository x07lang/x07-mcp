# MCP Conformance Harness

This directory pins and runs the upstream MCP conformance suite in **server mode**
against an x07-mcp Streamable HTTP server.

Upstream: `@modelcontextprotocol/conformance` (pinned). The conformance runner supports
an **expected failures** file; failures not listed there fail the run, and "expected failures"
that stop failing also fail the run (stale baseline).

## Pinned tool versions

- `@modelcontextprotocol/conformance@0.1.13`

## Quickstart (local)

1) Run against an already running server:

   `./conformance/run_server_conformance.sh --url http://127.0.0.1:8080/mcp`

2) Or let the harness spawn a reference server:

   `./conformance/run_server_conformance.sh --url http://127.0.0.1:8080/mcp --spawn postgres-mcp --mode noauth`

## Baseline policy

- Keep `conformance-baseline.yml` tiny.
- Delete entries as soon as the feature lands.
- Never baseline a real regression.

## CI usage pattern

- Start server in background
- Wait for port to respond (any status other than 000 is "up")
- Run conformance with `--expected-failures conformance-baseline.yml`
- Store `results/**/checks.json` as an artifact
