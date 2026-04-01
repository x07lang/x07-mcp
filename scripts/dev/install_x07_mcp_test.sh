#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${X07_MCP_TEST_TAG:-v0.1.0-alpha.4}}"
if [[ "${tag}" != v* ]]; then
  tag="v${tag}"
fi

platform="$(uname -s)"
arch="$(uname -m)"

artifact_platform=""
case "${platform}-${arch}" in
  Linux-x86_64) artifact_platform="linux-x64" ;;
  Darwin-arm64) artifact_platform="darwin-arm64" ;;
  Darwin-x86_64) artifact_platform="darwin-x64" ;;
  *)
    echo "ERROR: unsupported platform/arch: ${platform}-${arch}" >&2
    echo "NOTE: on Windows, use WSL2 and the linux-x64 artifact." >&2
    exit 2
    ;;
esac

asset="x07-mcp-test-${tag}-${artifact_platform}.tar.gz"
base_url="https://github.com/x07lang/x07-mcp-test/releases/download/${tag}"

install_dir="${X07_MCP_TEST_INSTALL_DIR:-${HOME}/.local/bin}"
install_path="${install_dir}/x07-mcp-test"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

archive_path="${tmp_dir}/${asset}"
checksums_path="${tmp_dir}/checksums.txt"

echo "==> download ${asset}"
curl -fSL \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 3 \
  --retry-delay 2 \
  --retry-all-errors \
  --output "${archive_path}" \
  "${base_url}/${asset}"

echo "==> download checksums.txt"
curl -fSL \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 3 \
  --retry-delay 2 \
  --retry-all-errors \
  --output "${checksums_path}" \
  "${base_url}/checksums.txt"

expected_line="$(grep -E "^[a-f0-9]{64}  ${asset}$" "${checksums_path}" | head -n 1 || true)"
if [[ -z "${expected_line}" ]]; then
  echo "ERROR: checksums.txt does not contain an entry for ${asset}" >&2
  exit 2
fi

echo "==> verify checksum"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "${tmp_dir}"
    printf '%s\n' "${expected_line}" | sha256sum -c - >/dev/null
  )
elif command -v shasum >/dev/null 2>&1; then
  expected_hash="$(printf '%s\n' "${expected_line}" | awk '{print $1}')"
  actual_hash="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
  if [[ "${expected_hash}" != "${actual_hash}" ]]; then
    echo "ERROR: sha256 mismatch for ${asset}" >&2
    exit 2
  fi
else
  echo "WARN: sha256sum/shasum not found; skipping checksum verification" >&2
fi

echo "==> install ${install_path}"
mkdir -p "${install_dir}"
tar -xzf "${archive_path}" -C "${tmp_dir}"
cp "${tmp_dir}/x07-mcp-test" "${install_path}"
chmod +x "${install_path}"

echo "==> ok: ${install_path}"
"${install_path}" --help >/dev/null
