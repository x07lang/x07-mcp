#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="demos/postgres-public-beta/out"
SERVER_ROOT="servers/postgres-mcp"
TARGET_URL="http://127.0.0.1:8403/mcp"

require_bin() {
  if [[ "${1}" == */* ]]; then
    if [[ ! -x "${1}" ]]; then
      echo "error: missing required executable: ${1}" >&2
      exit 2
    fi
    return 0
  fi
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "error: missing required command: ${1}" >&2
    exit 2
  fi
}

VERIFIER_BIN="${HARDPROOF_BIN:-hardproof}"
if [[ -z "${HARDPROOF_BIN:-}" && -x "${ROOT}/../x07-mcp-test/out/hardproof" ]]; then
  VERIFIER_BIN="${ROOT}/../x07-mcp-test/out/hardproof"
fi

require_bin "${VERIFIER_BIN}"

cd "${ROOT}"
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

run_logged "${VERIFIER_BIN}" scan --url "${TARGET_URL}" --out "${OUT_DIR}/conformance" --machine json

run_logged "${VERIFIER_BIN}" replay record \
  --url "${TARGET_URL}" \
  --scenario smoke/basic \
  --sanitize auth,token \
  --out "${OUT_DIR}/replay.session.json" \
  --machine json

run_logged "${VERIFIER_BIN}" replay verify \
  --session "${OUT_DIR}/replay.session.json" \
  --url "${TARGET_URL}" \
  --out "${OUT_DIR}/replay-verify" \
  --machine json

(
  cd "${SERVER_ROOT}"
  X07_MCP_X07_EXE="$(command -v x07)" ./publish/build_mcpb.sh
)

run_logged "${VERIFIER_BIN}" trust verify \
  --server-json "${SERVER_ROOT}/dist/server.json" \
  --machine json \
  --out "${OUT_DIR}/trust.summary.json"

run_logged "${VERIFIER_BIN}" bundle verify \
  --server-json "${SERVER_ROOT}/dist/server.json" \
  --mcpb "${SERVER_ROOT}/dist/postgres-mcp.mcpb" \
  --machine json \
  --out "${OUT_DIR}/bundle.verify.json"
