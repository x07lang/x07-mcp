#!/usr/bin/env bash
set -euo pipefail

URL="${1:?missing URL}"
TRIES="${TRIES:-960}"
SLEEP_SECS="${SLEEP_SECS:-0.25}"

for ((i=1; i<=TRIES; i++)); do
  # We accept ANY HTTP code as "server is up"; curl exits non-zero only for network errors.
  code="$(curl -s -o /dev/null -w "%{http_code}" "${URL}" || true)"
  if [[ "${code}" != "000" ]]; then
    echo "Server is responding at ${URL} (HTTP ${code})"
    exit 0
  fi
  sleep "${SLEEP_SECS}"
done

echo "Timed out waiting for ${URL}"
exit 1
