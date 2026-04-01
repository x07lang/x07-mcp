# Internal demo dry run (M1 Week 4)

Goal: rehearse the private-alpha end-to-end flow from a cold start with the real `x07-mcp-test` alpha release.

This is intentionally scoped to one example server and one happy-path verifier run.

## Demo flow (Codespaces)

### 1) Open the Codespace

- `https://codespaces.new/x07lang/x07-mcp?quickstart=1`

### 2) Install the verifier

From the repo root:

```sh
./scripts/dev/install_x07_mcp_test.sh
```

Expected:
- `x07-mcp-test --help` works
- `x07-mcp-test doctor --machine json` succeeds

### 3) Build and run the example server

```sh
cd examples/private-alpha-http-hello
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
./out/mcp-router
```

Expected:
- server listens on `http://127.0.0.1:8314/mcp`

### 4) Run conformance

In another terminal:

```sh
x07-mcp-test conformance run --url "http://127.0.0.1:8314/mcp" --out out/conformance --machine json
```

Expected artifacts:
- `out/conformance/summary.json`
- `out/conformance/summary.junit.xml`
- `out/conformance/summary.html`

## Notes

- Conformance runs via `npx`; `x07-mcp-test doctor` checks Node/npm/npx prerequisites.
- Windows support is via WSL2 (run inside the Linux distro).
