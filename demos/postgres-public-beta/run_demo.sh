#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${DEMO_ROOT}/out"
SERVER_ROOT="${ROOT}/servers/postgres-mcp"

usage() {
  cat <<'EOF' >&2
usage: run_demo.sh [--deps-only] [--server]

--deps-only  Start the Postgres dependency (Docker Compose) and exit.
--server     Build and run the Postgres MCP server (HTTP on 127.0.0.1:8403/mcp).
EOF
}

start_deps() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker is required for this demo" >&2
    exit 2
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "error: docker compose is required for this demo" >&2
    exit 2
  fi

  (
    cd "${DEMO_ROOT}"
    docker compose up -d
  )
}

build_server() {
  if ! command -v x07 >/dev/null 2>&1; then
    echo "error: x07 is required (install the X07 toolchain first)" >&2
    exit 2
  fi

  mkdir -p "${OUT_DIR}"

  (
    cd "${SERVER_ROOT}"
    x07 pkg lock --project x07.json
    x07 bundle --project x07.json --profile os --out out/postgres-mcp
    x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
  )
}

run_server() {
  (
    cd "${SERVER_ROOT}"
    export X07_MCP_CFG_PATH="config/mcp.server.http.json"
    exec ./out/postgres-mcp
  )
}

mode_deps_only=0
mode_server=0
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --deps-only) mode_deps_only=1 ;;
    --server) mode_server=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown arg: ${1}" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ "${mode_deps_only}" -eq 0 && "${mode_server}" -eq 0 ]]; then
  usage
  exit 2
fi

start_deps

if [[ "${mode_deps_only}" -eq 1 ]]; then
  exit 0
fi

build_server
run_server
