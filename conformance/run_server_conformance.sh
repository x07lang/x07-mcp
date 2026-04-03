#!/usr/bin/env bash
set -euo pipefail

# NOTE: x07-mcp still pins the official MCP conformance tool for client suites:
#   @modelcontextprotocol/conformance@0.1.14
# Server conformance runs use Hardproof to avoid a Node.js dependency.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:8080/mcp"
BASELINE="${ROOT}/conformance/conformance-baseline.yml"
RESULTS_DIR="${ROOT}/conformance/results"
SPAWN_SERVER=""
SPAWN_MODE="noauth"
URL_EXPLICIT=0
FULL_SUITE=0
PRINT_URL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?missing value for --url}"
      URL_EXPLICIT=1
      shift 2
      ;;
    --baseline)
      BASELINE="${2:?missing value for --baseline}"
      shift 2
      ;;
    --results-dir)
      RESULTS_DIR="${2:?missing value for --results-dir}"
      shift 2
      ;;
    --spawn)
      SPAWN_SERVER="${2:?missing value for --spawn}"
      shift 2
      ;;
    --mode)
      SPAWN_MODE="${2:?missing value for --mode}"
      shift 2
      ;;
    --full-suite)
      FULL_SUITE=1
      shift
      ;;
    --print-url)
      PRINT_URL=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${BASELINE}" != /* ]]; then
  BASELINE="${ROOT}/${BASELINE#./}"
fi
if [[ "${RESULTS_DIR}" != /* ]]; then
  RESULTS_DIR="${ROOT}/${RESULTS_DIR#./}"
fi

mkdir -p "${RESULTS_DIR}"

pushd "${ROOT}/conformance" >/dev/null

bg_pid=""
if [[ "${URL_EXPLICIT}" != "1" && -n "${SPAWN_SERVER}" ]]; then
  cfg_rel="config/mcp.server.http.json"
  if [[ "${SPAWN_MODE}" == "oauth" ]]; then
    cfg_rel="config/mcp.server.http.oauth.json"
  fi
  cfg_path="${ROOT}/servers/${SPAWN_SERVER}/${cfg_rel}"
  if [[ -f "${cfg_path}" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.transport != null' "${cfg_path}" >/dev/null 2>&1; then
      bind_host="$(jq -r '.transport.bind_host // "127.0.0.1"' "${cfg_path}")"
      bind_port="$(jq -r '.transport.bind_port // 8080' "${cfg_path}")"
      mcp_path="$(jq -r '.transport.mcp_path // "/mcp"' "${cfg_path}")"
      URL="http://${bind_host}:${bind_port}${mcp_path}"
    else
      bind="$(jq -r '.transports.http.bind // empty' "${cfg_path}")"
      mcp_path="$(jq -r '.transports.http.path // "/mcp"' "${cfg_path}")"
      if [[ -n "${bind}" ]]; then
        bind_host=""
        bind_port=""
        if [[ "${bind}" == \[*\]* ]]; then
          bind_host="${bind%%]*}"
          bind_host="${bind_host#[}"
          bind_port="${bind##*]:}"
        else
          bind_host="${bind%:*}"
          bind_port="${bind##*:}"
        fi
        if [[ "${bind_host}" == "0.0.0.0" || "${bind_host}" == "::" ]]; then
          bind_host="127.0.0.1"
        fi
        if [[ -n "${bind_port}" ]]; then
          URL="http://${bind_host}:${bind_port}${mcp_path}"
        fi
      fi
    fi
  fi
fi

if [[ "${PRINT_URL}" == "1" ]]; then
  echo "${URL}"
  exit 0
fi

start_spawn() {
  if [[ -n "${bg_pid}" ]]; then
    return 0
  fi
  local server_log="/tmp/x07-mcp-conformance-server.log"
  ./spawn_reference_http.sh "${SPAWN_SERVER}" "${SPAWN_MODE}" >"${server_log}" 2>&1 &
  bg_pid="$!"
  if ! ./wait_for_http.sh "${URL}" >/dev/null; then
    echo "ERROR: spawned server did not become ready at ${URL}" >&2
    if [[ -f "${server_log}" ]]; then
      echo "---- begin spawned server log ----" >&2
      tail -n 200 "${server_log}" >&2 || true
      echo "---- end spawned server log ----" >&2
    fi
    return 1
  fi
}

stop_spawn() {
  if [[ -n "${bg_pid}" ]]; then
    kill "${bg_pid}" >/dev/null 2>&1 || true
    wait "${bg_pid}" >/dev/null 2>&1 || true
    bg_pid=""
  fi
}

trap 'stop_spawn' EXIT

if [[ "${FULL_SUITE}" == "1" && -n "${SPAWN_SERVER}" ]]; then
  start_spawn
fi

hardproof_bin="${HARDPROOF_BIN:-hardproof}"
if ! command -v "${hardproof_bin}" >/dev/null 2>&1; then
  echo "ERROR: hardproof not found on PATH (expected ${hardproof_bin})." >&2
  echo "Hint: install Hardproof and retry." >&2
  exit 2
fi

rm -rf "${RESULTS_DIR}"
mkdir -p "${RESULTS_DIR}"

if [[ -n "${SPAWN_SERVER}" ]]; then
  start_spawn
fi

args=(scan --url "${URL}" --out "${RESULTS_DIR}" --machine json)
if [[ -n "${BASELINE}" ]]; then
  args+=(--baseline "${BASELINE}")
fi
if [[ "${FULL_SUITE}" == "1" ]]; then
  args+=(--full-suite)
fi
set -o pipefail
"${hardproof_bin}" "${args[@]}" | tee "${RESULTS_DIR}/summary.stdout.json" >/dev/null

stop_spawn

popd >/dev/null
