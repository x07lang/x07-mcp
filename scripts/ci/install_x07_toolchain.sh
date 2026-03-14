#!/usr/bin/env bash
set -euo pipefail

tag="${X07_TOOLCHAIN_TAG:-}"
tarball="${X07_TOOLCHAIN_TARBALL_LINUX_X64:-}"

if [[ -z "${tag}" || -z "${tarball}" ]]; then
  echo "ERROR: missing X07_TOOLCHAIN_TAG or X07_TOOLCHAIN_TARBALL_LINUX_X64" >&2
  exit 2
fi

install_root="${X07_TOOLCHAIN_INSTALL_ROOT:-$HOME/.x07}"
install_bin="${install_root}/bin"
x07_bin="${install_bin}/x07"

mkdir -p "${install_root}"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${install_bin}" >>"${GITHUB_PATH}"
else
  export PATH="${install_bin}:${PATH}"
fi

if [[ -x "${x07_bin}" ]]; then
  if "${x07_bin}" --version; then
    exit 0
  fi
  echo "WARN: cached x07 toolchain is invalid; reinstalling" >&2
fi

url="https://github.com/x07lang/x07/releases/download/${tag}/${tarball}"
retries="${X07_MCP_CURL_RETRIES:-5}"
delay_secs="${X07_MCP_CURL_RETRY_DELAY_SECS:-3}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
archive_path="${tmp_dir}/x07.tgz"

attempt=1
while true; do
  echo "==> download x07 toolchain (${tag}) attempt ${attempt}/${retries}"
  rm -f "${archive_path}"
  if curl -fSL \
    --connect-timeout 10 \
    --max-time 600 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    --output "${archive_path}" \
    "${url}"; then
    if tar -tzf "${archive_path}" >/dev/null 2>&1; then
      tar -xzf "${archive_path}" -C "${install_root}"
      break
    fi
  fi

  if [[ "${attempt}" -ge "${retries}" ]]; then
    echo "ERROR: failed to install x07 toolchain after ${attempt} attempts: ${url}" >&2
    exit 1
  fi

  echo "WARN: x07 toolchain install failed; retrying in ${delay_secs}s" >&2
  sleep "${delay_secs}"
  attempt="$((attempt + 1))"
done

if [[ ! -x "${x07_bin}" ]]; then
  echo "ERROR: x07 binary not found after install: ${x07_bin}" >&2
  exit 1
fi

"${x07_bin}" --version
