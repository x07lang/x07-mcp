#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_DIR="${1:?usage: install_server_deps.sh <server-dir>}"

if [[ ! -d "${SERVER_DIR}" ]]; then
  echo "ERROR: server dir not found: ${SERVER_DIR}" >&2
  exit 2
fi

SERVER_DIR_ABS="$(cd "${SERVER_DIR}" && pwd)"
SERVER_MANIFEST="${SERVER_DIR_ABS}/x07.json"
if [[ ! -f "${SERVER_MANIFEST}" ]]; then
  echo "ERROR: server manifest not found: ${SERVER_MANIFEST}" >&2
  exit 2
fi
cd "${SERVER_DIR_ABS}"

retry() {
  local retries="${1:-3}"
  local delay_secs="${2:-2}"
  shift 2

  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "${attempt}" -ge "${retries}" ]]; then
      return 1
    fi
    echo "WARN: retrying ($attempt/$retries) in ${delay_secs}s: $*" >&2
    sleep "${delay_secs}"
    attempt="$((attempt + 1))"
  done
}

check_project_lock() {
  local check_args=("$@")
  local lock_output
  set +e
  lock_output="$("${check_args[@]}" 2>&1)"
  local status=$?
  set -e
  if [[ "${status}" -ne 0 ]]; then
    printf '%s\n' "${lock_output}" >&2
    return "${status}"
  fi
}

if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  "${ROOT}/scripts/ci/materialize_project_local_deps.sh" "${SERVER_MANIFEST}"
  X07_WORKSPACE_ROOT="${ROOT}" \
    X07_MCP_USE_WORKSPACE_PATCH_DEPS=1 \
    X07_MCP_LOCAL_DEPS_REFRESH="${X07_MCP_LOCAL_DEPS_REFRESH:-0}" \
    "${ROOT}/scripts/ci/materialize_patch_deps.sh" "${SERVER_MANIFEST}"
  retries="${X07_MCP_LOCK_RETRIES:-3}"
  delay_secs="${X07_MCP_LOCK_RETRY_DELAY_SECS:-2}"
  if ! retry "${retries}" "${delay_secs}" check_project_lock x07 pkg lock --project "${SERVER_MANIFEST}" --check --json=off; then
    echo "ERROR: failed to validate local deps for ${SERVER_DIR} after ${retries} attempts" >&2
    exit 1
  fi
else
  retries="${X07_MCP_LOCK_RETRIES:-3}"
  delay_secs="${X07_MCP_LOCK_RETRY_DELAY_SECS:-2}"
  if ! retry "${retries}" "${delay_secs}" check_project_lock x07 pkg lock --project "${SERVER_MANIFEST}" --check --json=off; then
    echo "ERROR: failed to hydrate deps for ${SERVER_DIR} after ${retries} attempts" >&2
    exit 1
  fi
fi
