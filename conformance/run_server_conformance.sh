#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:8080/mcp"
BASELINE="${ROOT}/conformance/conformance-baseline.yml"
RESULTS_DIR="${ROOT}/conformance/results"
SPAWN_SERVER=""
SPAWN_MODE="noauth"
URL_EXPLICIT=0
FULL_SUITE=0
SCENARIOS=()

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
    --scenario)
      SCENARIOS+=("${2:?missing value for --scenario}")
      shift 2
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
    bind_host="$(jq -r '.transport.bind_host // "127.0.0.1"' "${cfg_path}")"
    bind_port="$(jq -r '.transport.bind_port // 8080' "${cfg_path}")"
    mcp_path="$(jq -r '.transport.mcp_path // "/mcp"' "${cfg_path}")"
    URL="http://${bind_host}:${bind_port}${mcp_path}"
  fi
fi

start_spawn() {
  if [[ -n "${bg_pid}" ]]; then
    return 0
  fi
  ./spawn_reference_http.sh "${SPAWN_SERVER}" "${SPAWN_MODE}" >/tmp/x07-mcp-conformance-server.log 2>&1 &
  bg_pid="$!"
  ./wait_for_http.sh "${URL}" >/dev/null
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

# NOTE: npx -y avoids prompting and keeps CI deterministic.
if [[ "${FULL_SUITE}" == "1" ]]; then
  npx -y @modelcontextprotocol/conformance@0.1.13 \
    server \
    --url "${URL}" \
    --expected-failures "${BASELINE}" \
    --output-dir "${RESULTS_DIR}/full-suite"
else
  if [[ "${#SCENARIOS[@]}" -eq 0 ]]; then
    SCENARIOS=(
      server-initialize
      ping
      tools-list
      tools-call-with-progress
      resources-subscribe
      resources-unsubscribe
      server-sse-multiple-streams
      dns-rebinding-protection
    )
  fi
  for scenario in "${SCENARIOS[@]}"; do
    if [[ -n "${SPAWN_SERVER}" ]]; then
      start_spawn
    fi
    npx -y @modelcontextprotocol/conformance@0.1.13 \
      server \
      --url "${URL}" \
      --scenario "${scenario}" \
      --output-dir "${RESULTS_DIR}/${scenario}" \
      --expected-failures "${BASELINE}"
    if [[ -n "${SPAWN_SERVER}" ]]; then
      stop_spawn
    fi
  done
fi

latest_checks="$(find . -type f -name checks.json | head -n 1 || true)"
if [[ -n "${latest_checks}" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp "${latest_checks}" "${RESULTS_DIR}/checks-${stamp}.json"
fi

stop_spawn

popd >/dev/null
