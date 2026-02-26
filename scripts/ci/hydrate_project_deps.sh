#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

project="${1:-}"
if [[ -z "${project}" ]]; then
  echo "usage: hydrate_project_deps.sh <project-x07.json>" >&2
  exit 2
fi

retries="${X07_MCP_LOCK_RETRIES:-3}"
delay_secs="${X07_MCP_LOCK_RETRY_DELAY_SECS:-2}"

attempt=1
while true; do
  if ./scripts/ci/materialize_patch_deps.sh "${project}" && x07 pkg lock --project "${project}" --check --json=off; then
    break
  fi

  if [[ "${attempt}" -ge "${retries}" ]]; then
    echo "ERROR: failed to hydrate deps for ${project} after ${attempt} attempts" >&2
    exit 1
  fi

  echo "WARN: hydrate_project_deps attempt ${attempt}/${retries} failed; retrying in ${delay_secs}s" >&2
  sleep "${delay_secs}"
  attempt="$((attempt + 1))"
done
