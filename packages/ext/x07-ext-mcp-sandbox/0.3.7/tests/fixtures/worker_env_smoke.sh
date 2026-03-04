#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _req || true

home_present=0
if [[ -n "${HOME:-}" ]]; then
  home_present=1
fi

allow_keys_has_home=0
if [[ "${X07_OS_ENV_ALLOW_KEYS:-}" == *"HOME"* ]]; then
  allow_keys_has_home=1
fi

printf '{"toolResult":{"content":[{"type":"text","text":"home_present=%s allow_keys_has_home=%s"}]}}' \
  "${home_present}" \
  "${allow_keys_has_home}"

