# Demo video script (Postgres public beta)

This is the draft script for a short (≈3 minute) “hero path” video that shows:

- one real MCP server (Postgres),
- Hardproof producing repeatable artifacts (JSON/JUnit/HTML/SARIF),
- replay evidence, and
- trust + bundle validation on release-like metadata.

## Pre-flight (before recording)

- Start from a clean `x07lang/x07-mcp` checkout.
- Ensure `x07` and `hardproof` are installed and on `PATH`.
- Confirm Docker is running.

## Recording flow

### 0:00 — framing

- “Ship MCP servers you can verify.”
- “Official MCP provides the baseline; x07 adds replay, trust, and release-grade validation artifacts.”

### 0:15 — start dependencies

```sh
cd demos/postgres-public-beta
./scripts/run_demo.sh --deps-only
```

### 0:25 — build + run the server

In one terminal:

```sh
./scripts/run_demo.sh --server
```

Call out:
- the endpoint `http://127.0.0.1:8403/mcp`
- that the same router/worker model is used across x07 reference servers

### 1:10 — conformance + replay evidence

In another terminal:

```sh
./scripts/verify_demo.sh
```

Call out the artifacts in `demos/postgres-public-beta/out/`:
- `conformance/summary.json`
- `conformance/summary.junit.xml`
- `conformance/summary.html`
- `conformance/summary.sarif.json`
- `replay.session.json`
- `replay-verify/verify.json`

### 2:15 — trust + bundle validation

Call out:
- `trust.summary.json` (trust metadata present + pinned)
- `bundle.verify.json` (server.json ↔ `.mcpb` consistency via SHA-256)

### 2:40 — close

- “This is the production verification layer on top of official MCP.”
- Point viewers at:
  - the demo README: `demos/postgres-public-beta/README.md`
  - the verifier repo: `x07lang/x07-mcp-test` (Hardproof)
