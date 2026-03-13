#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR=""
OUT=""
MACHINE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-dir)
      SERVER_DIR="${2:?missing value for --server-dir}"
      shift 2
      ;;
    --out)
      OUT="${2:?missing value for --out}"
      shift 2
      ;;
    --machine)
      MACHINE="${2:?missing value for --machine}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${SERVER_DIR}" ]]; then
  echo "usage: build_from_server_dir.sh --server-dir <path> [--out <path>] [--machine json]" >&2
  exit 2
fi

SERVER_DIR="$(cd "${SERVER_DIR}" && pwd)"
if [[ -n "${MACHINE}" && "${MACHINE}" != "json" ]]; then
  echo "unsupported --machine value: ${MACHINE}" >&2
  exit 2
fi
if [[ ! -x "${SERVER_DIR}/publish/build_mcpb.sh" ]]; then
  echo "ERROR: missing executable build script: ${SERVER_DIR}/publish/build_mcpb.sh" >&2
  exit 2
fi

BUILD_LOG=""
cleanup() {
  if [[ -n "${BUILD_LOG}" ]]; then
    rm -f "${BUILD_LOG}"
  fi
}
trap cleanup EXIT

if [[ "${MACHINE}" == "json" ]]; then
  BUILD_LOG="$(mktemp)"
  if ! "${SERVER_DIR}/publish/build_mcpb.sh" >"${BUILD_LOG}" 2>&1; then
    cat "${BUILD_LOG}" >&2
    exit 1
  fi
else
  "${SERVER_DIR}/publish/build_mcpb.sh"
fi

server_id="$(basename "${SERVER_DIR}")"
built="${SERVER_DIR}/dist/${server_id}.mcpb"
if [[ ! -f "${built}" ]]; then
  echo "ERROR: expected bundle not found: ${built}" >&2
  exit 2
fi

if [[ -n "${OUT}" ]]; then
  mkdir -p "$(dirname "${OUT}")"
  cp "${built}" "${OUT}"
  final_path="${OUT}"
else
  final_path="${built}"
fi

if [[ "${MACHINE}" == "json" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  python3 "${ROOT}/registry/scripts/bundle_summary.py" \
    --server-dir "${SERVER_DIR}" \
    --server-json "${SERVER_DIR}/dist/server.json" \
    --mcpb "${final_path}" \
    --machine json
else
  echo "${final_path}"
fi
