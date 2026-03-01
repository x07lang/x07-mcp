#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_DIR="${1:?usage: install_server_deps.sh <server-dir>}"

if [[ ! -d "${SERVER_DIR}" ]]; then
  echo "ERROR: server dir not found: ${SERVER_DIR}" >&2
  exit 2
fi

SERVER_DIR_ABS="$(cd "${SERVER_DIR}" && pwd)"
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

copy_local_pkg_if_present() {
  local name="$1"
  local version="$2"
  local target_dir="$3"
  local candidate

  for candidate in \
    "${ROOT}/packages/ext/x07-${name}/${version}" \
    "${ROOT}/../x07/packages/ext/x07-${name}/${version}"
  do
    if [[ -d "${candidate}" ]]; then
      mkdir -p "$(dirname "${target_dir}")"
      rm -rf "${target_dir}"
      cp -R "${candidate}" "${target_dir}"
      return 0
    fi
  done
  return 1
}

materialize_local_deps_from_workspace() {
  local server_dir_abs="$1"
  local x07_root="${ROOT}/../x07"

  if [[ ! -d "${x07_root}" ]]; then
    echo "ERROR: local-deps mode requires x07 checkout at ${x07_root}" >&2
    return 2
  fi

  while IFS=$'\t' read -r name version path_value; do
    [[ -n "${name}" && -n "${version}" && -n "${path_value}" ]] || continue
    local dst="${server_dir_abs}/${path_value}"
    if [[ -d "${dst}" ]]; then
      continue
    fi
    if ! copy_local_pkg_if_present "${name}" "${version}" "${dst}"; then
      echo "ERROR: missing local package: ${name}@${version} (expected under x07-mcp or x07 workspace)" >&2
      return 2
    fi
  done < <(jq -r '.dependencies[] | [.name, .version, .path] | @tsv' "${server_dir_abs}/x07.json")
}

if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  materialize_local_deps_from_workspace "${SERVER_DIR_ABS}"
  x07 pkg lock --project x07.json --check --offline --json=off >/dev/null
else
  retries="${X07_MCP_LOCK_RETRIES:-3}"
  delay_secs="${X07_MCP_LOCK_RETRY_DELAY_SECS:-2}"
  if ! retry "${retries}" "${delay_secs}" x07 pkg lock --project x07.json --check --json=off; then
    echo "ERROR: failed to hydrate deps for ${SERVER_DIR} after ${retries} attempts" >&2
    exit 1
  fi
fi
