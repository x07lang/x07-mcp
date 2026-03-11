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

  x07_meta_count="$(jq '[._meta["io.modelcontextprotocol.registry/publisher-provided"].x07? | select(type=="object")] | length' "${server_json}")"
  legacy_prm_count="$(jq '[._meta["io.modelcontextprotocol.registry/publisher-provided"]["x07.io/mcp"].prm? | select(type=="object")] | length' "${server_json}")"
  if [[ "${x07_meta_count}" -eq 0 && "${legacy_prm_count}" -eq 0 ]]; then
    echo "ERROR: ${server_json} missing _meta publisher trust summary (x07 or x07.io/mcp.prm)" >&2
    status=1
    continue
  fi

  require_signed="$(jq -r '
    ._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.requireSignedPrm //
    ._meta["io.modelcontextprotocol.registry/publisher-provided"]["x07.io/mcp"].prm.requireSigned //
    empty
  ' "${server_json}")"
  if [[ "${require_signed}" != "true" ]]; then
    echo "ERROR: ${server_json} requires requireSignedPrm=true in publisher trust summary" >&2
    status=1
  fi

  trust_framework_sha="$(jq -r '
    ._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustFrameworkSha256 //
    ._meta["io.modelcontextprotocol.registry/publisher-provided"]["x07.io/mcp"].prm.trustFrameworkSha256 //
    empty
  ' "${server_json}")"
  if [[ -z "${trust_framework_sha}" ]]; then
    echo "ERROR: ${server_json} missing trustFrameworkSha256 in publisher trust summary" >&2
    status=1
  elif [[ ! "${trust_framework_sha}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: ${server_json} trustFrameworkSha256 must be 64 lowercase hex chars" >&2
    status=1
  elif [[ "${trust_framework_sha}" == "${PLACEHOLDER_SHA}" ]]; then
    echo "ERROR: ${server_json} contains placeholder trustFrameworkSha256" >&2
    status=1
  fi

  trust_lock_sha="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustLockSha256 // empty' "${server_json}")"
  if [[ -n "${trust_lock_sha}" ]]; then
    if [[ ! "${trust_lock_sha}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "ERROR: ${server_json} trustLockSha256 must be 64 lowercase hex chars" >&2
      status=1
    elif [[ "${trust_lock_sha}" == "${PLACEHOLDER_SHA}" ]]; then
      echo "ERROR: ${server_json} contains placeholder trustLockSha256" >&2
      status=1
    fi
  fi

  trust_pack_count="$(jq '[._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack? | select(type=="object")] | length' "${server_json}")"
  if [[ "${trust_pack_count}" -gt 0 ]]; then
    trust_pack_version="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack.packVersion // empty' "${server_json}")"
    if [[ -z "${trust_pack_version}" ]]; then
      echo "ERROR: ${server_json} trustPack.packVersion is required when trustPack metadata is present" >&2
      status=1
    fi

    trust_pack_lock_sha="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack.lockSha256 // empty' "${server_json}")"
    if [[ -z "${trust_pack_lock_sha}" ]]; then
      echo "ERROR: ${server_json} trustPack.lockSha256 is required when trustPack metadata is present" >&2
      status=1
    elif [[ ! "${trust_pack_lock_sha}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "ERROR: ${server_json} trustPack.lockSha256 must be 64 lowercase hex chars" >&2
      status=1
    elif [[ "${trust_pack_lock_sha}" == "${PLACEHOLDER_SHA}" ]]; then
      echo "ERROR: ${server_json} contains placeholder trustPack.lockSha256" >&2
      status=1
    fi

    trust_pack_min_snapshot="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack.minSnapshotVersion // empty' "${server_json}")"
    if [[ -z "${trust_pack_min_snapshot}" ]]; then
      echo "ERROR: ${server_json} trustPack.minSnapshotVersion is required when trustPack metadata is present" >&2
      status=1
    elif ! [[ "${trust_pack_min_snapshot}" =~ ^[0-9]+$ ]] || [[ "${trust_pack_min_snapshot}" -le 0 ]]; then
      echo "ERROR: ${server_json} trustPack.minSnapshotVersion must be an integer > 0" >&2
      status=1
    fi

    trust_pack_snapshot_sha="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack.snapshotSha256 // empty' "${server_json}")"
    if [[ -z "${trust_pack_snapshot_sha}" ]]; then
      echo "ERROR: ${server_json} trustPack.snapshotSha256 is required when trustPack metadata is present" >&2
      status=1
    elif [[ ! "${trust_pack_snapshot_sha}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "ERROR: ${server_json} trustPack.snapshotSha256 must be 64 lowercase hex chars" >&2
      status=1
    elif [[ "${trust_pack_snapshot_sha}" == "${PLACEHOLDER_SHA}" ]]; then
      echo "ERROR: ${server_json} contains placeholder trustPack.snapshotSha256" >&2
      status=1
    fi

    trust_pack_checkpoint_sha="$(jq -r '._meta["io.modelcontextprotocol.registry/publisher-provided"].x07.trustPack.checkpointSha256 // empty' "${server_json}")"
    if [[ -z "${trust_pack_checkpoint_sha}" ]]; then
      echo "ERROR: ${server_json} trustPack.checkpointSha256 is required when trustPack metadata is present" >&2
      status=1
    elif [[ ! "${trust_pack_checkpoint_sha}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "ERROR: ${server_json} trustPack.checkpointSha256 must be 64 lowercase hex chars" >&2
      status=1
    elif [[ "${trust_pack_checkpoint_sha}" == "${PLACEHOLDER_SHA}" ]]; then
      echo "ERROR: ${server_json} contains placeholder trustPack.checkpointSha256" >&2
      status=1
    fi
  fi
done

if [[ "${status}" -ne 0 ]]; then
  exit 1
fi

echo "ok: release metadata guard passed"
