#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

root="$(repo_root)"
cd "$root"

bad=0

check_file() {
  local f="$1"
  if grep -q '"test_fixed_nonce"' "$f"; then
    echo "ERROR: release config must not include test_fixed_nonce: $f" >&2
    bad=1
  fi
}

while IFS= read -r -d '' f; do
  check_file "$f"
done < <(
  find templates servers \
    -type f -name '*.json' \
    ! -path '*/tests/*' \
    ! -path '*/fixtures/*' \
    -print0
)

exit "$bad"
