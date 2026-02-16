#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_ID="${1:?missing server id}"
VERSION="${2:?missing version}"
SERVER_ROOT="${ROOT}/servers/${SERVER_ID}"
OUT_DIR="${SERVER_ROOT}/dist"
OUT_FILE="${OUT_DIR}/${SERVER_ID}.mcpb"

mkdir -p "${OUT_DIR}"

ROUTER_BIN="${SERVER_ROOT}/out/${SERVER_ID}"
WORKER_BIN="${SERVER_ROOT}/out/${SERVER_ID}-worker"

if [[ ! -x "${ROUTER_BIN}" ]]; then
  x07 bundle --project "${SERVER_ROOT}/x07.json" --profile os --out "${ROUTER_BIN}" >/dev/null
fi
if [[ ! -x "${WORKER_BIN}" ]]; then
  (
    cd "${SERVER_ROOT}"
    x07 bundle \
      --profile sandbox \
      --sandbox-backend os \
      --i-accept-weaker-isolation \
      --program src/worker_main.x07.json \
      --module-root src \
      --module-root tests \
      --out "${WORKER_BIN}" >/dev/null
  )
fi

STAGE="$(mktemp -d)"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

mkdir -p "${STAGE}/server" "${STAGE}/config" "${STAGE}/policy" "${STAGE}/arch/budgets"
cp "${SERVER_ROOT}/publish/manifest.json" "${STAGE}/manifest.json"
cp "${ROUTER_BIN}" "${STAGE}/server/${SERVER_ID}"
cp "${WORKER_BIN}" "${STAGE}/server/${SERVER_ID}-worker"
cp -R "${SERVER_ROOT}/config/." "${STAGE}/config/"
cp -R "${SERVER_ROOT}/policy/." "${STAGE}/policy/"
cp -R "${SERVER_ROOT}/arch/budgets/." "${STAGE}/arch/budgets/"

find "${STAGE}" -exec touch -t 200001010000 {} +

npx -y @anthropic-ai/mcpb@2.1.2 pack "${STAGE}" "${OUT_FILE}"

shasum -a 256 "${OUT_FILE}" | awk '{print $1}' > "${OUT_FILE}.sha256.txt"
echo "built ${OUT_FILE}"
