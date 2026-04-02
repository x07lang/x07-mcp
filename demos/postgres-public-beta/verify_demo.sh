#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${DEMO_ROOT}/out"
SERVER_ROOT="${ROOT}/servers/postgres-mcp"
TARGET_URL="http://127.0.0.1:8403/mcp"

require_cmd() {
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "error: missing required command: ${1}" >&2
    exit 2
  fi
}

require_cmd x07-mcp-test

mkdir -p "${OUT_DIR}"

cmd_log="${OUT_DIR}/command.log"
rm -f "${cmd_log}"

run_logged() {
  printf '$' >>"${cmd_log}"
  for arg in "$@"; do
    printf ' %q' "${arg}" >>"${cmd_log}"
  done
  printf '\n' >>"${cmd_log}"
  "$@" 2>&1 | tee -a "${cmd_log}"
}

run_logged x07-mcp-test conformance run --url "${TARGET_URL}" --out "${OUT_DIR}/conformance" --machine json

run_logged x07-mcp-test replay record \
  --url "${TARGET_URL}" \
  --scenario smoke/basic \
  --sanitize auth,token \
  --out "${OUT_DIR}/replay.session.json" \
  --machine json

run_logged x07-mcp-test replay verify \
  --session "${OUT_DIR}/replay.session.json" \
  --url "${TARGET_URL}" \
  --out "${OUT_DIR}/replay-verify" \
  --machine json

(
  cd "${SERVER_ROOT}"
  ./publish/build_mcpb.sh
)

run_logged x07-mcp-test trust verify \
  --server-json "${SERVER_ROOT}/dist/server.json" \
  --machine json \
  --out "${OUT_DIR}/trust.summary.json"

run_logged x07-mcp-test bundle verify \
  --server-json "${SERVER_ROOT}/dist/server.json" \
  --mcpb "${SERVER_ROOT}/dist/postgres-mcp.mcpb" \
  --machine json \
  --out "${OUT_DIR}/bundle.verify.json"
