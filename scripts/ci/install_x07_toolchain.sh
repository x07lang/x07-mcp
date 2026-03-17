#!/usr/bin/env bash
set -euo pipefail

tag="${X07_TOOLCHAIN_TAG:-}"
tarball="${X07_TOOLCHAIN_TARBALL_LINUX_X64:-}"
source_dir="${X07_TOOLCHAIN_SOURCE_DIR:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -n "${source_dir}" && "${source_dir}" != /* ]]; then
  source_dir="${repo_root}/${source_dir}"
fi

if [[ -z "${source_dir}" && ( -z "${tag}" || -z "${tarball}" ) ]]; then
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
  if [[ -n "${source_dir}" ]]; then
    version="${tag#v}"
    staged_stdlib_lock="${install_root}/toolchains/v${version}/stdlib.lock"
    if [[ -n "${version}" && -f "${staged_stdlib_lock}" ]] && "${x07_bin}" --version; then
      exit 0
    fi
  elif "${x07_bin}" --version; then
    exit 0
  fi
  echo "WARN: cached x07 toolchain is invalid; reinstalling" >&2
fi

if [[ -n "${source_dir}" ]]; then
  if [[ ! -d "${source_dir}/crates/x07" ]]; then
    echo "ERROR: invalid X07_TOOLCHAIN_SOURCE_DIR (missing crates/x07): ${source_dir}" >&2
    exit 2
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo is required when X07_TOOLCHAIN_SOURCE_DIR is set" >&2
    exit 2
  fi

  version="${tag#v}"
  if [[ -z "${version}" ]]; then
    version="$(grep -m1 '^version = "' "${source_dir}/crates/x07/Cargo.toml" | sed -E 's/^version = "([^"]+)".*$/\1/')"
  fi
  if [[ -z "${version}" ]]; then
    echo "ERROR: failed to determine toolchain version from source checkout" >&2
    exit 2
  fi

  echo "==> install x07 toolchain from source checkout (${source_dir})"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07c"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07-host-runner"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07-os-runner"

  toolchain_dir="${install_root}/toolchains/v${version}"
  rm -rf "${toolchain_dir}"
  mkdir -p "${toolchain_dir}/bin"
  for bin_name in x07 x07c x07-host-runner x07-os-runner; do
    cp "${install_bin}/${bin_name}" "${toolchain_dir}/bin/${bin_name}"
  done
  for file_name in README.md stdlib.lock stdlib.os.lock; do
    if [[ -f "${source_dir}/${file_name}" ]]; then
      cp "${source_dir}/${file_name}" "${toolchain_dir}/${file_name}"
    fi
  done
  for dir_name in .agent deps spec stdlib; do
    if [[ -d "${source_dir}/${dir_name}" ]]; then
      cp -R "${source_dir}/${dir_name}" "${toolchain_dir}/${dir_name}"
    fi
  done

  "${x07_bin}" --version
  exit 0
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
