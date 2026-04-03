# private-alpha HTTP hello

Minimal HTTP MCP server example in pure X07, derived from `templates/mcp-server-http/`.

- Endpoint: `http://127.0.0.1:8314/mcp`
- Router/worker split: router on host OS, tool execution in sandboxed worker
- Tools: exposes exactly one tool (`hello.work`)

For the full template documentation (OAuth, trust, replay fixtures, publish), see `templates/mcp-server-http/README.md`.

## Quickstart (Codespaces)

Install the verifier (once per Codespace):

```sh
./scripts/dev/install_hardproof.sh
```

Build and run the server:

```sh
cd examples/private-alpha-http-hello
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
./out/mcp-router
```

Run conformance in another terminal:

```sh
hardproof scan --url "http://127.0.0.1:8314/mcp" --out out/conformance
```

Artifacts are written under `out/conformance/` (`summary.json`, `summary.junit.xml`, `summary.html`).

## Optional: record + replay

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

## Config notes

- Server config: `config/mcp.server.json` (no-auth quickstart)
- Tools manifest: `config/mcp.tools.json` (only `hello.work`)
- Worker binary path: `worker_exe_path = "out/mcp-worker"` (relative to this directory)
