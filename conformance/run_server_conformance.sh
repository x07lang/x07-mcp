#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:8080/mcp"
BASELINE="${ROOT}/conformance/conformance-baseline.yml"
RESULTS_DIR="${ROOT}/conformance/results"
SPAWN_SERVER=""
SPAWN_MODE="noauth"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?missing value for --url}"
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
if [[ -n "${SPAWN_SERVER}" ]]; then
  ./spawn_reference_http.sh "${SPAWN_SERVER}" "${SPAWN_MODE}" >/tmp/x07-mcp-conformance-server.log 2>&1 &
  bg_pid="$!"
  trap 'if [[ -n "${bg_pid}" ]]; then kill "${bg_pid}" >/dev/null 2>&1 || true; fi' EXIT
  ./wait_for_http.sh "${URL}" >/dev/null
fi

# NOTE: npx -y avoids prompting and keeps CI deterministic.
npx -y @modelcontextprotocol/conformance@0.1.13 \
  server \
  --url "${URL}" \
  --expected-failures "${BASELINE}"

latest_checks="$(find . -type f -name checks.json | head -n 1 || true)"
if [[ -n "${latest_checks}" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp "${latest_checks}" "${RESULTS_DIR}/checks-${stamp}.json"
fi

if [[ -n "${bg_pid}" ]]; then
  kill "${bg_pid}" >/dev/null 2>&1 || true
  wait "${bg_pid}" >/dev/null 2>&1 || true
fi

popd >/dev/null
