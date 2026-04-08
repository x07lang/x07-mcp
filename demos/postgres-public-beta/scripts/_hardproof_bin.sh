require_bin() {
  if [[ "${1}" == */* ]]; then
    if [[ ! -x "${1}" ]]; then
      echo "error: missing required executable: ${1}" >&2
      exit 2
    fi
    return 0
  fi
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "error: missing required command: ${1}" >&2
    exit 2
  fi
}

hardproof_bin_version() {
  local bin="${1:?missing hardproof bin}"
  local out

  out="$("${bin}" --version 2>/dev/null)" || return 1
  # Expected: "hardproof X.Y.Z-..."
  printf '%s\n' "${out}" | awk '{print $2}'
}

hardproof_expected_version_from_sibling() {
  local hardproof_root="${1:?missing hardproof repo root}"
  local version_file="${hardproof_root}/scripts/ci/check_example_artifacts.py"
  local line

  if [[ ! -f "${version_file}" ]]; then
    return 0
  fi

  line="$(grep -E '^CURRENT_TOOL_VERSION\\s*=\\s*"' "${version_file}" | head -n 1 || true)"
  if [[ -z "${line}" ]]; then
    return 0
  fi

  printf '%s\n' "${line}" | sed -E 's/.*"([^"]+)".*/\\1/'
}

resolve_hardproof_bin() {
  local workspace_root="${1:?missing workspace root}"

  if [[ -n "${HARDPROOF_BIN:-}" ]]; then
    require_bin "${HARDPROOF_BIN}"
    printf '%s\n' "${HARDPROOF_BIN}"
    return 0
  fi

  if command -v hardproof >/dev/null 2>&1; then
    printf '%s\n' hardproof
    return 0
  fi

  local local_install="${HOME}/.local/bin/hardproof"
  if [[ -x "${local_install}" ]]; then
    printf '%s\n' "${local_install}"
    return 0
  fi

  local sibling_root="${workspace_root}/../hardproof"
  local sibling_bin="${sibling_root}/out/hardproof"
  if [[ -x "${sibling_bin}" ]]; then
    local expected
    expected="$(hardproof_expected_version_from_sibling "${sibling_root}")"
    if [[ -n "${expected}" ]]; then
      local got
      got="$(hardproof_bin_version "${sibling_bin}" || true)"
      if [[ "${got}" == "${expected}" ]]; then
        printf '%s\n' "${sibling_bin}"
        return 0
      fi
      echo "error: ${sibling_bin} version mismatch (got ${got:-unknown}, expected ${expected})" >&2
      echo "hint: build Hardproof from ${sibling_root} or install a matching release via scripts/dev/install_hardproof.sh" >&2
      return 2
    fi

    printf '%s\n' "${sibling_bin}"
    return 0
  fi

  echo "error: Hardproof binary not found" >&2
  echo "hint: install Hardproof via ./scripts/dev/install_hardproof.sh and ensure it is on PATH (or set HARDPROOF_BIN)" >&2
  return 2
}

