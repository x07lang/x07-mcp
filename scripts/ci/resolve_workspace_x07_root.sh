#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

emit_candidate() {
  local candidate="$1"
  [[ -n "${candidate}" ]] || return 1
  if [[ ! -d "${candidate}" ]]; then
    return 1
  fi
  if [[ -d "${candidate}/crates/x07" && -f "${candidate}/stdlib.lock" ]]; then
    cd "${candidate}" && pwd
    return 0
  fi
  return 1
}

if [[ -n "${X07_ROOT:-}" ]]; then
  if [[ "${X07_ROOT}" = /* ]]; then
    if emit_candidate "${X07_ROOT}"; then
      exit 0
    fi
  else
    if emit_candidate "${PWD}/${X07_ROOT}"; then
      exit 0
    fi
    if emit_candidate "${ROOT}/${X07_ROOT}"; then
      exit 0
    fi
  fi
fi

if emit_candidate "${ROOT}/x07"; then
  exit 0
fi

if emit_candidate "${ROOT}/../x07"; then
  exit 0
fi

echo "ERROR: missing local x07 checkout near ${ROOT}" >&2
exit 2
