#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${HARDPROOF_TAG:-latest-beta}}"
if [[ "${tag}" != v* && "${tag}" != latest-alpha && "${tag}" != latest-beta ]]; then
  tag="v${tag}"
fi

bootstrap_tag="${tag}"
if [[ "${tag}" == "latest-beta" || "${tag}" == latest-beta* ]]; then
  bootstrap_tag="${HARDPROOF_BOOTSTRAP_BETA_TAG:-v0.3.0-beta.0}"
elif [[ "${tag}" == "latest-alpha" || "${tag}" == latest-alpha* ]]; then
  bootstrap_tag="${HARDPROOF_BOOTSTRAP_ALPHA_TAG:-v0.1.0-alpha.9}"
fi

install_dir="${HARDPROOF_INSTALL_DIR:-${HOME}/.local/bin}"
install_path="${install_dir}/hardproof"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

script_url="https://github.com/x07lang/hardproof/releases/download/${bootstrap_tag}/install.sh"
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
