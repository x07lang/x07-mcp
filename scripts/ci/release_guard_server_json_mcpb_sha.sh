#!/usr/bin/env bash
set -euo pipefail

# Guards the committed server registry manifests against a placeholder, empty, or
# malformed mcpb fileSha256 before a release ships.
#
# This runs on tag push (release-guards.yml), where the gitignored dist/ build
# output and the not-yet-created GitHub release asset are both unavailable -- so
# it checks the committed servers/*/publish/server.mcp-registry.json. The full
# "sha matches the actual mcpb (and its .sha256.txt)" chain is covered elsewhere:
# `x07-mcp publish --dry-run` in ci/check (post-build, against dist/) and the
# verify-release-asset workflow (against the published .mcpb on the release).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLACEHOLDER_SHA="0000000000000000000000000000000000000000000000000000000000000000"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 2
  fi
}

require_cmd jq

server_json_files=()
while IFS= read -r server_json; do
  server_json_files+=("$server_json")
done < <(find "$ROOT/servers" -type f -path '*/publish/server.mcp-registry.json' | sort)

if [[ ${#server_json_files[@]} -eq 0 ]]; then
  echo "ERROR: no publish/server.mcp-registry.json files found under $ROOT/servers/*/" >&2
  exit 2
fi

status=0
for server_json in "${server_json_files[@]}"; do
  shas=()
  while IFS= read -r sha; do
    shas+=("$sha")
  done < <(jq -r '.packages[]? | select(.registryType=="mcpb") | (.fileSha256 // "")' "$server_json")

  if [[ ${#shas[@]} -ne 1 ]]; then
    echo "ERROR: $server_json must have exactly 1 mcpb package entry (got ${#shas[@]})" >&2
    status=1
    continue
  fi

  sha_from_json="${shas[0]}"
  if [[ -z "$sha_from_json" ]]; then
    echo "ERROR: $server_json has an empty mcpb fileSha256" >&2
    status=1
    continue
  fi
  if [[ "$sha_from_json" == "$PLACEHOLDER_SHA" ]]; then
    echo "ERROR: $server_json contains placeholder mcpb fileSha256" >&2
    status=1
    continue
  fi
  if [[ ! "$sha_from_json" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: $server_json mcpb fileSha256 must be 64 lowercase hex chars (got: $sha_from_json)" >&2
    status=1
    continue
  fi

  echo "ok: $server_json mcpb fileSha256 is well-formed ($sha_from_json)"
done

if [[ "$status" -ne 0 ]]; then
  exit 1
fi

echo "ok: committed server.mcp-registry.json mcpb shas are well-formed"
