#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEARCH_ROOT="${1:-${ROOT}}"
PLACEHOLDER_SHA="0000000000000000000000000000000000000000000000000000000000000000"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: missing command: jq" >&2
  exit 2
fi

server_json_files=()
while IFS= read -r server_json; do
  server_json_files+=("${server_json}")
done < <(find "${SEARCH_ROOT}" -type f -name 'server.json' | sort)

if [[ ${#server_json_files[@]} -eq 0 ]]; then
  echo "ERROR: no server.json files found under ${SEARCH_ROOT}" >&2
  exit 1
fi

status=0
for server_json in "${server_json_files[@]}"; do
  mcpb_count="$(jq '[.packages[]? | select(.registryType=="mcpb")] | length' "${server_json}")"
  if [[ "${mcpb_count}" -eq 0 ]]; then
    echo "ERROR: ${server_json} has no mcpb package entry" >&2
    status=1
    continue
  fi

  while IFS= read -r sha; do
    if [[ -z "${sha}" ]]; then
      echo "ERROR: ${server_json} has an empty mcpb fileSha256" >&2
      status=1
      continue
    fi
    if [[ "${sha}" == "${PLACEHOLDER_SHA}" ]]; then
      echo "ERROR: ${server_json} contains placeholder mcpb fileSha256" >&2
      status=1
    fi
  done < <(jq -r '.packages[]? | select(.registryType=="mcpb") | (.fileSha256 // "")' "${server_json}")
done

if [[ "${status}" -ne 0 ]]; then
  exit 1
fi

echo "ok: release metadata guard passed"
