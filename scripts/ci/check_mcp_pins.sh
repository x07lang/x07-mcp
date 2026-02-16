#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN_FILE="${ROOT}/arch/pins/mcp_kit.json"

schema_url="$(jq -r '.registry.server_schema_url' "${PIN_FILE}")"
schema_file="$(jq -r '.registry.server_schema_file' "${PIN_FILE}")"
conformance_pin="$(jq -r '.tools.conformance_npx' "${PIN_FILE}")"
mcpb_pin="$(jq -r '.tools.mcpb_npx' "${PIN_FILE}")"

[[ -f "${ROOT}/${schema_file}" ]] || {
  echo "ERROR: pinned schema file missing: ${schema_file}" >&2
  exit 1
}

while IFS= read -r fixture; do
  got="$(jq -r '."$schema"' "${fixture}")"
  if [[ "${got}" != "${schema_url}" ]]; then
    echo "ERROR: schema mismatch in fixture ${fixture}" >&2
    exit 1
  fi
done < <(find "${ROOT}/registry/fixtures" -type f -name expected.server.json | sort)

grep -q "${conformance_pin}" "${ROOT}/conformance/run_server_conformance.sh" || {
  echo "ERROR: conformance pin missing from conformance script" >&2
  exit 1
}

grep -q "${mcpb_pin}" "${ROOT}/servers/_shared/publish/build_mcpb_common.sh" || {
  echo "ERROR: MCPB pin missing from build script" >&2
  exit 1
}

grep -q "${schema_url}" "${ROOT}/docs/reference/pins.md" || {
  echo "ERROR: schema pin missing from docs/reference/pins.md" >&2
  exit 1
}

grep -q "${conformance_pin}" "${ROOT}/docs/reference/pins.md" || {
  echo "ERROR: conformance pin missing from docs/reference/pins.md" >&2
  exit 1
}

grep -q "${mcpb_pin}" "${ROOT}/docs/reference/pins.md" || {
  echo "ERROR: MCPB pin missing from docs/reference/pins.md" >&2
  exit 1
}

echo "ok: MCP pins are consistent"
