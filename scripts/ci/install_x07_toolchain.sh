#!/usr/bin/env bash
set -euo pipefail

tag="${X07_TOOLCHAIN_TAG:-}"
tarball="${X07_TOOLCHAIN_TARBALL_LINUX_X64:-}"
source_dir="${X07_TOOLCHAIN_SOURCE_DIR:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -n "${source_dir}" && "${source_dir}" != /* ]]; then
  source_dir="${repo_root}/${source_dir}"
fi

python_bin="${X07_PYTHON:-}"
if [[ -z "${python_bin}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  fi
fi

native_backend_relpaths() {
  local manifest_path="$1"
  local platform_key=""
  case "$(uname -s)" in
    Linux) platform_key="linux" ;;
    Darwin) platform_key="macos" ;;
    MINGW*|MSYS*|CYGWIN*) platform_key="windows" ;;
    *)
      echo "ERROR: unsupported platform for native backend staging: $(uname -s)" >&2
      exit 2
      ;;
  esac

  if [[ -z "${python_bin}" ]]; then
    echo "ERROR: python3 or python is required to read ${manifest_path}" >&2
    exit 2
  fi

  "${python_bin}" - "$manifest_path" "$platform_key" <<'PY'
import json
import sys

path = sys.argv[1]
platform_key = sys.argv[2]
doc = json.load(open(path, "r", encoding="utf-8"))
files = []
for backend in doc.get("backends") or []:
    link = backend.get("link") or {}
    spec = link.get(platform_key) or {}
    files.extend(spec.get("files") or [])
for rel in sorted(set(files)):
    print(rel)
PY
}

native_backend_build_script() {
  local relpath="$1"
  local base="${relpath##*/}"
  base="${base%.a}"
  base="${base%.lib}"
  case "${base}" in
    libx07_ext_*)
      printf 'build_%s.sh\n' "${base#libx07_}"
      ;;
    libx07_math)
      printf 'build_ext_math.sh\n'
      ;;
    libx07_stream_xf)
      printf 'build_ext_stream_xf.sh\n'
      ;;
    libx07_time)
      printf 'build_ext_time.sh\n'
      ;;
    *)
      return 1
      ;;
  esac
}

toolchain_tree_complete() {
  local tree_root="$1"
  local manifest_path="$tree_root/deps/x07/native_backends.json"
  local relpath=""

  [[ -f "$manifest_path" ]] || return 1
  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    [[ -f "$tree_root/$relpath" ]] || return 1
  done < <(native_backend_relpaths "$manifest_path")

  local helper=""
  for helper in x07-proc-echo x07-proc-worker-frame-echo; do
    if [[ -x "$tree_root/deps/x07/$helper" || -x "$tree_root/deps/x07/$helper.exe" ]]; then
      continue
    fi
    return 1
  done

  return 0
}

ensure_source_toolchain_artifacts() {
  local manifest_path="$source_dir/deps/x07/native_backends.json"
  local relpath=""
  local build_script=""
  local built_helpers="0"

  [[ -f "$manifest_path" ]] || {
    echo "ERROR: missing native backends manifest in source checkout: ${manifest_path}" >&2
    exit 2
  }

  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    if [[ -f "$source_dir/$relpath" ]]; then
      continue
    fi
    build_script="$(native_backend_build_script "$relpath")" || {
      echo "ERROR: no build script mapping for native backend artifact: ${relpath}" >&2
      exit 2
    }
    if [[ ! -x "$source_dir/scripts/$build_script" ]]; then
      echo "ERROR: missing native backend build script: ${source_dir}/scripts/${build_script}" >&2
      exit 2
    fi
    (
      cd "$source_dir"
      "./scripts/${build_script}" >/dev/null
    )
  done < <(native_backend_relpaths "$manifest_path")

  local helper=""
  for helper in x07-proc-echo x07-proc-worker-frame-echo; do
    if [[ -x "$source_dir/deps/x07/$helper" || -x "$source_dir/deps/x07/$helper.exe" ]]; then
      continue
    fi
    if [[ "$built_helpers" == "0" ]]; then
      (
        cd "$source_dir"
        ./scripts/build_os_helpers.sh >/dev/null
      )
      built_helpers="1"
    fi
  done
}

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

version=""
if [[ -n "${source_dir}" ]]; then
  if [[ ! -d "${source_dir}/crates/x07" ]]; then
    echo "ERROR: invalid X07_TOOLCHAIN_SOURCE_DIR (missing crates/x07): ${source_dir}" >&2
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
fi

if [[ -x "${x07_bin}" ]]; then
  if [[ -n "${source_dir}" ]]; then
    staged_stdlib_lock="${install_root}/toolchains/v${version}/stdlib.lock"
    root_stdlib_lock="${install_root}/stdlib.lock"
    toolchain_dir="${install_root}/toolchains/v${version}"
    if [[ -f "${staged_stdlib_lock}" && -f "${root_stdlib_lock}" ]] \
      && toolchain_tree_complete "${install_root}" \
      && toolchain_tree_complete "${toolchain_dir}" \
      && "${x07_bin}" --version; then
      exit 0
    fi
  elif "${x07_bin}" --version; then
    exit 0
  fi
  echo "WARN: cached x07 toolchain is invalid; reinstalling" >&2
fi

if [[ -n "${source_dir}" ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo is required when X07_TOOLCHAIN_SOURCE_DIR is set" >&2
    exit 2
  fi

  echo "==> install x07 toolchain from source checkout (${source_dir})"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07c"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07-host-runner"
  cargo install --locked --root "${install_root}" --path "${source_dir}/crates/x07-os-runner"
  ensure_source_toolchain_artifacts

  stage_source_toolchain_tree() {
    local dest_root="$1"
    mkdir -p "${dest_root}/bin"
    for bin_name in x07 x07c x07-host-runner x07-os-runner; do
      local src_bin="${install_bin}/${bin_name}"
      local dest_bin="${dest_root}/bin/${bin_name}"
      if [[ "${src_bin}" != "${dest_bin}" ]]; then
        cp "${src_bin}" "${dest_bin}"
      fi
    done
    for file_name in README.md stdlib.lock stdlib.os.lock; do
      if [[ -f "${source_dir}/${file_name}" ]]; then
        cp "${source_dir}/${file_name}" "${dest_root}/${file_name}"
      fi
    done
    for dir_name in .agent deps spec stdlib; do
      if [[ -d "${source_dir}/${dir_name}" ]]; then
        rm -rf "${dest_root}/${dir_name}"
        cp -R "${source_dir}/${dir_name}" "${dest_root}/${dir_name}"
      fi
    done
  }

  stage_source_toolchain_tree "${install_root}"

  toolchain_dir="${install_root}/toolchains/v${version}"
  rm -rf "${toolchain_dir}"
  stage_source_toolchain_tree "${toolchain_dir}"

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
