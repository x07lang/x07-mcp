#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pinned_x07_tag() {
  local toolchain_toml="${ROOT}/x07-toolchain.toml"
  [[ -f "${toolchain_toml}" ]] || return 0
  sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "${toolchain_toml}" | head -n 1
}

git_rev_parse_quiet() {
  local repo_root="$1"
  local rev="$2"
  git -C "${repo_root}" rev-parse "${rev}" 2>/dev/null | head -n 1
}

require_pinned_workspace_state() {
  local candidate="$1"
  local pinned_tag=""
  local head_sha=""
  local tag_sha=""
  local dirty=""

  pinned_tag="$(pinned_x07_tag)"
  [[ -n "${pinned_tag}" ]] || return 0

  if ! git -C "${candidate}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: workspace x07 checkout at ${candidate} is not a git repo; cannot verify pinned tag ${pinned_tag}" >&2
    return 1
  fi

  head_sha="$(git_rev_parse_quiet "${candidate}" "HEAD^{commit}")"
  tag_sha="$(git_rev_parse_quiet "${candidate}" "${pinned_tag}^{commit}")"
  if [[ -z "${tag_sha}" ]]; then
    echo "ERROR: workspace x07 checkout at ${candidate} is missing pinned tag ${pinned_tag}; set X07_ROOT to a matching worktree" >&2
    return 1
  fi

  if [[ "${head_sha}" != "${tag_sha}" ]]; then
    echo "ERROR: workspace x07 checkout at ${candidate} is not at pinned tag ${pinned_tag} (head=${head_sha:0:12} tag=${tag_sha:0:12}); checkout ${pinned_tag} or set X07_ROOT to a matching worktree" >&2
    return 1
  fi

  dirty="$(git -C "${candidate}" status --short --untracked-files=no 2>/dev/null)"
  if [[ -n "${dirty}" ]]; then
    echo "ERROR: workspace x07 checkout at ${candidate} has tracked local modifications; use a clean ${pinned_tag} worktree for x07-mcp checks" >&2
    return 1
  fi
}

emit_candidate() {
  local candidate="$1"
  [[ -n "${candidate}" ]] || return 1
  if [[ ! -d "${candidate}" ]]; then
    return 1
  fi
  if [[ -d "${candidate}/crates/x07" && -f "${candidate}/stdlib.lock" ]]; then
    require_pinned_workspace_state "${candidate}" || return 2
    cd "${candidate}" && pwd
    return 0
  fi
  return 1
}

capture_emit_candidate() {
  local candidate="$1"
  local status=0
  emit_candidate "${candidate}" || status="$?"
  return "${status}"
}

if [[ -n "${X07_ROOT:-}" ]]; then
  if [[ "${X07_ROOT}" = /* ]]; then
    status=0
    capture_emit_candidate "${X07_ROOT}" || status="$?"
    if [[ "${status}" -eq 0 ]]; then
      exit 0
    fi
    if [[ "${status}" -eq 2 ]]; then
      exit 2
    fi
  else
    status=0
    capture_emit_candidate "${PWD}/${X07_ROOT}" || status="$?"
    if [[ "${status}" -eq 0 ]]; then
      exit 0
    fi
    if [[ "${status}" -eq 2 ]]; then
      exit 2
    fi
    status=0
    capture_emit_candidate "${ROOT}/${X07_ROOT}" || status="$?"
    if [[ "${status}" -eq 0 ]]; then
      exit 0
    fi
    if [[ "${status}" -eq 2 ]]; then
      exit 2
    fi
  fi
fi

status=0
capture_emit_candidate "${ROOT}/x07" || status="$?"
if [[ "${status}" -eq 0 ]]; then
  exit 0
fi
if [[ "${status}" -eq 2 ]]; then
  exit 2
fi

status=0
capture_emit_candidate "${ROOT}/../x07" || status="$?"
if [[ "${status}" -eq 0 ]]; then
  exit 0
fi
if [[ "${status}" -eq 2 ]]; then
  exit 2
fi

echo "ERROR: missing local x07 checkout near ${ROOT}" >&2
exit 2
