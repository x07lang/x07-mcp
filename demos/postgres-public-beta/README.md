# Postgres public-beta demo

This directory defines the public hero demo path and the verifier command sequence.

## Environment contract

This demo assumes:

- You are in the `x07lang/x07-mcp` repo.
- The X07 toolchain is installed (the demo uses `x07 bundle` and runs native bundles).
- Hardproof (`hardproof`) is installed on `PATH` (or installed via `./scripts/dev/install_hardproof.sh`). You can also override with `HARDPROOF_BIN=/path/to/hardproof`.
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

### 3) Verify the server with Hardproof

In another terminal:

```sh
./scripts/verify_demo.sh
```

If you are developing inside the multi-repo workspace (`x07lang/`), `verify_demo.sh` will prefer `../hardproof/out/hardproof` when present. Otherwise it uses `hardproof` from `PATH`.

Expected artifacts under `demos/postgres-public-beta/out/`:
- `scan/scan.json`
- `scan/scan.events.jsonl`
- `replay.session.json`
- `replay-verify/verify.json`
- `trust.summary.json`
- `bundle.verify.json`
- `command.log`

See `docs/public-beta/postgres-demo-expected-findings.md` for what to expect in the scan report.

### 3.1) Benchmarkable scan runs (optional)

To run repeated scans and keep per-run reports for perf/reliability comparisons:

```sh
./scripts/benchmark_scan.sh --runs 5
```

This writes per-run outputs under `demos/postgres-public-beta/out/bench/` and prints a compact summary after each run.

### 4) Capture outputs for website/content work

```sh
./scripts/capture_outputs.sh
```

This copies the verifier outputs plus a command log into `demos/postgres-public-beta/assets/captured/`.
