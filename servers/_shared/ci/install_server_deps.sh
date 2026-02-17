#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_DIR="${1:?usage: install_server_deps.sh <server-dir>}"

if [[ ! -d "${SERVER_DIR}" ]]; then
  echo "ERROR: server dir not found: ${SERVER_DIR}" >&2
  exit 2
fi

cd "${SERVER_DIR}"

install_local_pkg() {
  local name="$1"
  local version="$2"
  local src="$3"
  local dst=".x07/local/${name}/${version}"
  x07 pkg remove "${name}" >/dev/null 2>&1 || true
  rm -rf "${dst}"
  mkdir -p "$(dirname "${dst}")"
  cp -R "${src}" "${dst}"
  x07 pkg add "${name}@${version}" --path "${dst}" >/dev/null
}

install_sync_pkg() {
  local name="$1"
  local version="$2"
  x07 pkg remove "${name}" >/dev/null 2>&1 || true
  x07 pkg add "${name}@${version}" --sync >/dev/null
}

if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  X07_ROOT="$(cd "${ROOT}/../x07" && pwd)"
  install_local_pkg ext-jsonschema-rs 0.1.0 "${X07_ROOT}/packages/ext/x07-ext-jsonschema-rs/0.1.0"
  install_local_pkg ext-fs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-fs/0.1.4"
  install_local_pkg ext-data-model 0.1.8 "${X07_ROOT}/packages/ext/x07-ext-data-model/0.1.8"
  install_local_pkg ext-json-rs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-json-rs/0.1.4"
  install_local_pkg ext-net 0.1.8 "${X07_ROOT}/packages/ext/x07-ext-net/0.1.8"
  install_local_pkg ext-stdio 0.1.0 "${X07_ROOT}/packages/ext/x07-ext-stdio/0.1.0"
  install_local_pkg ext-csv-rs 0.1.5 "${X07_ROOT}/packages/ext/x07-ext-csv-rs/0.1.5"
  install_local_pkg ext-curl-c 0.1.6 "${X07_ROOT}/packages/ext/x07-ext-curl-c/0.1.6"
  install_local_pkg ext-ini-rs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-ini-rs/0.1.4"
  install_local_pkg ext-sockets-c 0.1.6 "${X07_ROOT}/packages/ext/x07-ext-sockets-c/0.1.6"
  install_local_pkg ext-toml-rs 0.1.5 "${X07_ROOT}/packages/ext/x07-ext-toml-rs/0.1.5"
  install_local_pkg ext-unicode-rs 0.1.5 "${X07_ROOT}/packages/ext/x07-ext-unicode-rs/0.1.5"
  install_local_pkg ext-url-rs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-url-rs/0.1.4"
  install_local_pkg ext-xml-rs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-xml-rs/0.1.4"
  install_local_pkg ext-yaml-rs 0.1.4 "${X07_ROOT}/packages/ext/x07-ext-yaml-rs/0.1.4"
  install_local_pkg ext-mcp-core 0.2.2 "${ROOT}/packages/ext/x07-ext-mcp-core/0.2.2"
  install_local_pkg ext-mcp-toolkit 0.2.2 "${ROOT}/packages/ext/x07-ext-mcp-toolkit/0.2.2"
  install_local_pkg ext-mcp-worker 0.2.2 "${ROOT}/packages/ext/x07-ext-mcp-worker/0.2.2"
  install_local_pkg ext-mcp-sandbox 0.2.2 "${ROOT}/packages/ext/x07-ext-mcp-sandbox/0.2.2"
  install_local_pkg ext-mcp-auth 0.1.0 "${ROOT}/packages/ext/x07-ext-mcp-auth/0.1.0"
  install_local_pkg ext-mcp-obs 0.1.0 "${ROOT}/packages/ext/x07-ext-mcp-obs/0.1.0"
  install_local_pkg ext-mcp-transport-http 0.2.0 "${ROOT}/packages/ext/x07-ext-mcp-transport-http/0.2.0"
  install_local_pkg ext-mcp-rr 0.2.2 "${ROOT}/packages/ext/x07-ext-mcp-rr/0.2.2"
  x07 pkg lock --project x07.json --offline >/dev/null
else
  install_sync_pkg ext-jsonschema-rs 0.1.0
  install_sync_pkg ext-fs 0.1.4
  install_sync_pkg ext-data-model 0.1.8
  install_sync_pkg ext-json-rs 0.1.4
  install_sync_pkg ext-net 0.1.8
  install_sync_pkg ext-stdio 0.1.0
  install_sync_pkg ext-csv-rs 0.1.5
  install_sync_pkg ext-curl-c 0.1.6
  install_sync_pkg ext-ini-rs 0.1.4
  install_sync_pkg ext-sockets-c 0.1.6
  install_sync_pkg ext-toml-rs 0.1.5
  install_sync_pkg ext-unicode-rs 0.1.5
  install_sync_pkg ext-url-rs 0.1.4
  install_sync_pkg ext-xml-rs 0.1.4
  install_sync_pkg ext-yaml-rs 0.1.4
  install_sync_pkg ext-mcp-core 0.2.2
  install_sync_pkg ext-mcp-toolkit 0.2.2
  install_sync_pkg ext-mcp-worker 0.2.2
  install_sync_pkg ext-mcp-sandbox 0.2.2
  install_sync_pkg ext-mcp-auth 0.1.0
  install_sync_pkg ext-mcp-obs 0.1.0
  install_sync_pkg ext-mcp-transport-http 0.2.0
  install_sync_pkg ext-mcp-rr 0.2.2
  x07 pkg lock --project x07.json >/dev/null
fi
