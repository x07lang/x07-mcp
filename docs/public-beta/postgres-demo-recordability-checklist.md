# Postgres demo: recordability checklist

This checklist is for recording a stable “verify then build” hero demo of the Postgres MCP server.

## Preconditions

- X07 toolchain installed (`x07 --version`).
- Hardproof installed (`hardproof --version`), or set `HARDPROOF_BIN=/path/to/hardproof`.
- Docker + Docker Compose installed.
- Port `8403` available for the MCP server.

## Frozen command sequence

From `x07-mcp/demos/postgres-public-beta/`:

```sh
./scripts/run_demo.sh --deps-only
./scripts/run_demo.sh --server
./scripts/verify_demo.sh
```

## Expected evidence artifacts

Under `demos/postgres-public-beta/out/`:

- `command.log` (exact command log)
- `replay.session.json` and `replay-verify/verify.json` (recorded + verified session)
- `scan/scan.json` and `scan/scan.events.jsonl` (scan report + events)
- `trust.summary.json` and `bundle.verify.json` (trust/bundle evidence)

To freeze outputs for website/content work:

```sh
./scripts/capture_outputs.sh
```

## Known caveats and flaky spots

- The current demo commonly warns on:
  - `TRUST-TRUSTPACK-MISSING` (no trust pack metadata provided)
  - `PERF-CONCURRENT-TOOLS-CALL-LOW` (concurrency probes are sensitive to local load)
- Usage metrics can be `estimate`, `tokenizer_exact`, `trace_observed`, or `mixed` (see `usage_mode`); estimate mode is a deterministic comparison signal, not billing-grade truth.
- If you omit trust inputs (`--server-json`, `--mcpb`), expect a partial score (`score_truth_status = "partial"`).

## Recording checklist

- Close CPU-heavy apps and avoid background builds while recording (perf probes are load-sensitive).
- Keep Docker resources stable (don’t change CPU/memory limits mid-run).
- Run the full sequence once “off camera” to ensure the environment is warm and the server is reachable.
- Record `demos/postgres-public-beta/out/command.log` alongside terminal output for reproducibility.

## Troubleshooting quick checks

- Postgres container is up: `docker compose ps` (from `demos/postgres-public-beta/`).
- Server is listening: `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8403/mcp`.
- If builds fail, re-run from a clean server build dir:
  - `rm -rf servers/postgres-mcp/out servers/postgres-mcp/.x07/tmp`
