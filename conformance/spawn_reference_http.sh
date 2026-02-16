#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_ID="${1:?missing server id}"
MODE="${2:?missing mode (noauth|oauth)}"

SERVER_ROOT="${ROOT}/servers/${SERVER_ID}"
if [[ ! -d "${SERVER_ROOT}" ]]; then
  echo "ERROR: server not found: ${SERVER_ROOT}" >&2
  exit 2
fi

CFG="config/mcp.server.http.json"
if [[ "${MODE}" == "oauth" ]]; then
  CFG="config/mcp.server.http.oauth.json"
elif [[ "${MODE}" == "noauth" ]]; then
  CFG="config/mcp.server.http.json"
else
  echo "ERROR: unknown mode: ${MODE}" >&2
  exit 2
fi

OUT_DIR="${SERVER_ROOT}/out"
mkdir -p "${OUT_DIR}"

"${ROOT}/servers/_shared/ci/install_server_deps.sh" "${SERVER_ROOT}"

echo "==> bundle router + worker (${SERVER_ID})"
x07 bundle --project "${SERVER_ROOT}/x07.json" --profile os --out "${OUT_DIR}/${SERVER_ID}" >/dev/null
(
  cd "${SERVER_ROOT}"
  x07 bundle \
    --profile sandbox \
    --sandbox-backend os \
    --i-accept-weaker-isolation \
    --program src/worker_main.x07.json \
    --module-root src \
    --module-root tests \
    --out "${OUT_DIR}/${SERVER_ID}-worker" >/dev/null
)

echo "==> run router (${SERVER_ID}, ${MODE})"
export X07_MCP_CFG_PATH="${CFG}"
cd "${SERVER_ROOT}"
exec "${OUT_DIR}/${SERVER_ID}"
