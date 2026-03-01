#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  if [[ -n "${X07_MCP_SECURITY_ROOT:-}" ]]; then
    cd "${X07_MCP_SECURITY_ROOT}" && pwd
    return
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

root="$(repo_root)"
cd "$root"

search_roots=()
if [[ "$#" -gt 0 ]]; then
  search_roots=("$@")
else
  search_roots=(templates packages servers publish conformance)
fi

bad=0
for r in "${search_roots[@]}"; do
  [[ -d "$r" ]] || continue
  while IFS= read -r -d '' f; do
    case "$f" in
      */tests/*|*/fixtures/*) continue ;;
    esac
    echo "ERROR: secret artifact must not be committed outside tests/fixtures: $f" >&2
    bad=1
  done < <(
    find "$r" \
      \( -type d \( -name .git -o -name .x07 -o -name target -o -name dist -o -name .agent_cache \) -prune \) -o \
      -type f -name '*.secret.b64' -print0
  )
done

if [[ "$bad" -ne 0 ]]; then
  exit 2
fi

echo "ok: no secret artifacts detected"
