#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${DEMO_ROOT}/out"
CAPTURE_DIR="${DEMO_ROOT}/assets/captured"

if [[ ! -d "${OUT_DIR}" ]]; then
  echo "error: missing out dir: ${OUT_DIR} (run scripts/verify_demo.sh first)" >&2
  exit 2
fi

rm -rf "${CAPTURE_DIR}"
mkdir -p "${CAPTURE_DIR}"

copy_if_exists() {
  local src="${1}"
  local dst="${2}"
  if [[ -e "${src}" ]]; then
    mkdir -p "$(dirname "${dst}")"
    cp -R "${src}" "${dst}"
  fi
}

copy_if_exists "${OUT_DIR}/command.log" "${CAPTURE_DIR}/command.log"
copy_if_exists "${OUT_DIR}/scan" "${CAPTURE_DIR}/scan"
copy_if_exists "${OUT_DIR}/replay.session.json" "${CAPTURE_DIR}/replay.session.json"
copy_if_exists "${OUT_DIR}/replay-verify" "${CAPTURE_DIR}/replay-verify"
copy_if_exists "${OUT_DIR}/trust.summary.json" "${CAPTURE_DIR}/trust.summary.json"
copy_if_exists "${OUT_DIR}/bundle.verify.json" "${CAPTURE_DIR}/bundle.verify.json"

printf 'captured outputs in %s\n' "${CAPTURE_DIR}"
