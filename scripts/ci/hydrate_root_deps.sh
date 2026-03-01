#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

retries="${X07_MCP_LOCK_RETRIES:-3}"
delay_secs="${X07_MCP_LOCK_RETRY_DELAY_SECS:-2}"

attempt=1
while true; do
  if x07 pkg lock --project x07.json --check --json=off; then
    break
  fi

  if [[ "${attempt}" -ge "${retries}" ]]; then
    echo "ERROR: failed to hydrate root dependencies after ${attempt} attempts" >&2
    exit 1
  fi

  echo "WARN: hydrate_root_deps attempt ${attempt}/${retries} failed; retrying in ${delay_secs}s" >&2
  sleep "${delay_secs}"
  attempt="$((attempt + 1))"
done
