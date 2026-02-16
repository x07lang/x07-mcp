#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVERS_DIR="${ROOT}/servers"

while IFS= read -r server_id; do
  echo
  echo "==> reference server: ${server_id}"
  server_dir="${SERVERS_DIR}/${server_id}"
  "${SERVERS_DIR}/_shared/ci/install_server_deps.sh" "${server_dir}"
  (
    cd "${server_dir}"
    x07 test --manifest tests/tests.json --json=off >/dev/null
  )
done < <(find "${SERVERS_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | grep -v '^_shared$')

echo
echo "ok: reference server tests passed"
