#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIR_DEFAULT="demos/postgres-public-beta/out/bench"
SERVER_ROOT="servers/postgres-mcp"
TARGET_URL="http://127.0.0.1:8403/mcp"

usage() {
  cat <<'EOF' >&2
usage: benchmark_scan.sh [--runs N] [--out DIR]

Runs Hardproof scan repeatedly against the Postgres demo target and stores each run under:
  <out>/run-<i>/

This is intended for repeatable perf/reliability comparisons across changes.
EOF
}

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

runs=5
out_dir="${OUT_DIR_DEFAULT}"
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --runs) runs="${2:-}"; shift ;;
    --out) out_dir="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown arg: ${1}" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ -z "${runs}" || "${runs}" -le 0 ]]; then
  echo "error: --runs must be a positive integer" >&2
  exit 2
fi

VERIFIER_BIN="${HARDPROOF_BIN:-hardproof}"
if [[ -z "${HARDPROOF_BIN:-}" && -x "${ROOT}/../hardproof/out/hardproof" ]]; then
  VERIFIER_BIN="${ROOT}/../hardproof/out/hardproof"
fi

require_bin "${VERIFIER_BIN}"

cd "${ROOT}"

(
  cd "${SERVER_ROOT}"
  X07_MCP_X07_EXE="$(command -v x07)" ./publish/build_mcpb.sh
)

rm -rf "${out_dir}"
mkdir -p "${out_dir}"

for i in $(seq 1 "${runs}"); do
  run_dir="${out_dir}/run-${i}"
  mkdir -p "${run_dir}"

  "${VERIFIER_BIN}" scan \
    --url "${TARGET_URL}" \
    --server-json "${SERVER_ROOT}/dist/server.json" \
    --mcpb "${SERVER_ROOT}/dist/postgres-mcp.mcpb" \
    --out "${run_dir}" \
    --format json >/dev/null

  "${VERIFIER_BIN}" report summary --input "${run_dir}/scan.json" --ui compact
done

printf 'wrote %d runs under %s\n' "${runs}" "${out_dir}"
