#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR=""
OUT=""

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
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${SERVER_DIR}" ]]; then
  echo "usage: build_from_server_dir.sh --server-dir <path> [--out <path>]" >&2
  exit 2
fi

SERVER_DIR="$(cd "${SERVER_DIR}" && pwd)"
if [[ ! -x "${SERVER_DIR}/publish/build_mcpb.sh" ]]; then
  echo "ERROR: missing executable build script: ${SERVER_DIR}/publish/build_mcpb.sh" >&2
  exit 2
fi

"${SERVER_DIR}/publish/build_mcpb.sh"

server_id="$(basename "${SERVER_DIR}")"
built="${SERVER_DIR}/dist/${server_id}.mcpb"
if [[ ! -f "${built}" ]]; then
  echo "ERROR: expected bundle not found: ${built}" >&2
  exit 2
fi

if [[ -n "${OUT}" ]]; then
  mkdir -p "$(dirname "${OUT}")"
  cp "${built}" "${OUT}"
  echo "${OUT}"
else
  echo "${built}"
fi
