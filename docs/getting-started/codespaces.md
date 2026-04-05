# Codespaces quickstart (public beta)

Zero-install evaluation path: run a minimal x07-native MCP HTTP server and verify it locally.

## 1) Open a Codespace

Use the badge in `README.md`, or open:

- `https://codespaces.new/x07lang/x07-mcp?quickstart=1`

## 2) Install the verifier (Hardproof)

From the repo root:

```sh
./scripts/dev/install_hardproof.sh
```

If `hardproof` is not on `PATH`, run:

```sh
~/.local/bin/hardproof --help
```

## 3) Build + run the example server

```sh
cd examples/private-alpha-http-hello
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
./out/mcp-router
```

The MCP endpoint is `http://127.0.0.1:8314/mcp`.

## 4) Run a scan

In another terminal:

```sh
hardproof scan --url "http://127.0.0.1:8314/mcp" --out out/scan
```

Artifacts are written under `out/scan/`:

- `scan.json`
- `scan.events.jsonl`

## 5) Optional: record + replay

Record a small HTTP session cassette:

```sh
hardproof replay record \
  --url "http://127.0.0.1:8314/mcp" \
  --scenario smoke/basic \
  --sanitize auth,token \
  --out out/replay.session.json \
  --machine json
```

Replay it against the same target:

```sh
hardproof replay verify \
  --session out/replay.session.json \
  --url "http://127.0.0.1:8314/mcp" \
  --out out/replay-verify \
  --machine json
```

Artifacts are written under `out/replay-verify/` (`verify.json`).
