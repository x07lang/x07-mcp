#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CODESPACES:-}" ]]; then
  echo "==> Codespaces detected (repo: x07-mcp)"
fi

cat <<'TXT'

==> MCP quickstart: verify with Hardproof

1) Install verifier:
  ./scripts/dev/install_hardproof.sh

2) Run the example server:
  cd examples/private-alpha-http-hello
  x07 bundle --project x07.json --profile os --out out/mcp-router
  x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
  ./out/mcp-router

3) Conformance (new terminal):
  hardproof scan --url "http://127.0.0.1:8314/mcp" --out out/conformance --machine json

Docs:
  docs/getting-started/codespaces.md
  docs/internal/demo-dry-run.md
TXT
