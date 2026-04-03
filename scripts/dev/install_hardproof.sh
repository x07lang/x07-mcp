#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${HARDPROOF_TAG:-v0.1.0-alpha.5}}"
if [[ "${tag}" != v* && "${tag}" != latest-alpha ]]; then
  tag="v${tag}"
fi

install_dir="${HARDPROOF_INSTALL_DIR:-${HOME}/.local/bin}"
install_path="${install_dir}/hardproof"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

script_url="https://github.com/x07lang/hardproof/releases/download/${tag}/install.sh"
script_path="${tmp_dir}/install.sh"

echo "==> download ${script_url}"
curl -fSL \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 3 \
  --retry-delay 2 \
  --retry-all-errors \
  --output "${script_path}" \
  "${script_url}"

chmod +x "${script_path}"
"${script_path}" --tag "${tag}" --install-dir "${install_dir}"

"${install_path}" --help >/dev/null
