# Codespaces quickstart (private alpha)

Zero-install evaluation path: run a minimal x07-native MCP HTTP server and verify it locally.

## 1) Open a Codespace

Use the badge in `README.md`, or open:

- `https://codespaces.new/x07lang/x07-mcp?quickstart=1`

## 2) Install the verifier (`x07-mcp-test`)

From the repo root:

```sh
./scripts/dev/install_x07_mcp_test.sh
```

If `x07-mcp-test` is not on `PATH`, run:

```sh
~/.local/bin/x07-mcp-test --help
```

## 3) Build + run the example server

```sh
cd examples/private-alpha-http-hello
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
./out/mcp-router
```

The MCP endpoint is `http://127.0.0.1:8314/mcp`.

## 4) Run conformance

In another terminal:

```sh
x07-mcp-test conformance run --url "http://127.0.0.1:8314/mcp" --out out/conformance
```

Artifacts are written under `out/conformance/`:

- `summary.json`
- `summary.junit.xml`
- `summary.html`

## 5) Optional: record + replay

Record a small HTTP session cassette:

```sh
x07-mcp-test replay record \
  --url "http://127.0.0.1:8314/mcp" \
  --scenario smoke/basic \
  --sanitize auth,token \
  --out out/replay.session.json \
  --machine json
```

Replay it against the same target:

```sh
x07-mcp-test replay verify \
  --session out/replay.session.json \
  --url "http://127.0.0.1:8314/mcp" \
  --out out/replay-verify \
  --machine json
```

Artifacts are written under `out/replay-verify/` (`verify.json`).
