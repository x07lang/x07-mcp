# Internal demo dry run

Goal: rehearse the private-alpha end-to-end flow from a cold start with a real Hardproof release.

This is intentionally scoped to one example server and one happy-path verifier run.

## Demo flow (Codespaces)

### 1) Open the Codespace

- `https://codespaces.new/x07lang/x07-mcp?quickstart=1`

### 2) Install the verifier

From the repo root:

```sh
./scripts/dev/install_hardproof.sh
```

Expected:
- `hardproof --help` works
- `hardproof doctor --machine json` succeeds

### 3) Build and run the example server

```sh
cd examples/private-alpha-http-hello
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
./out/mcp-router
```

Expected:
- server listens on `http://127.0.0.1:8314/mcp`

### 4) Run a scan

In another terminal:

```sh
hardproof scan --url "http://127.0.0.1:8314/mcp" --out out/scan --format json
```

Expected artifacts:
- `out/scan/scan.json`
- `out/scan/scan.events.jsonl`

## Notes

- Windows support is via WSL2 (run inside the Linux distro).
- Scan runs inside the `hardproof` binary; `hardproof doctor` checks environment and reachability prerequisites.
