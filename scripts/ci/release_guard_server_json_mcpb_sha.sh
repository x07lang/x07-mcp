#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLACEHOLDER_SHA="0000000000000000000000000000000000000000000000000000000000000000"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 2
  fi
}

require_cmd jq
require_cmd python3

server_json_files=()
while IFS= read -r server_json; do
  server_json_files+=("$server_json")
done < <(find "$ROOT/servers" -type f -path '*/dist/server.json' | sort)

if [[ ${#server_json_files[@]} -eq 0 ]]; then
  echo "ERROR: no server.json files found under $ROOT/servers/*/dist/" >&2
  exit 2
fi

status=0
for server_json in "${server_json_files[@]}"; do
  dist_dir="$(cd "$(dirname "$server_json")" && pwd)"

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
    echo "ERROR: $server_json mcpb fileSha256 must be 64 lowercase hex chars" >&2
    status=1
    continue
  fi

  mcpb_files=()
  while IFS= read -r mcpb; do
    mcpb_files+=("$mcpb")
  done < <(find "$dist_dir" -maxdepth 1 -type f -name '*.mcpb' | sort)

  if [[ ${#mcpb_files[@]} -ne 1 ]]; then
    echo "ERROR: $dist_dir must contain exactly 1 .mcpb file (got ${#mcpb_files[@]})" >&2
    status=1
    continue
  fi

  mcpb_path="${mcpb_files[0]}"
  sha_actual="$(
    python3 - "$mcpb_path" <<'PY'
import hashlib
import sys

path = sys.argv[1]
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
  )"

  if [[ "$sha_actual" != "$sha_from_json" ]]; then
    echo "ERROR: sha mismatch for $server_json (json=$sha_from_json actual=$sha_actual file=$mcpb_path)" >&2
    status=1
  fi

  sha_txt_files=()
  while IFS= read -r sha_txt; do
    sha_txt_files+=("$sha_txt")
  done < <(find "$dist_dir" -maxdepth 1 -type f -name '*.mcpb.sha256.txt' | sort)

  if [[ ${#sha_txt_files[@]} -ne 1 ]]; then
    echo "ERROR: $dist_dir must contain exactly 1 .mcpb.sha256.txt file (got ${#sha_txt_files[@]})" >&2
    status=1
    continue
  fi

  sha_txt_path="${sha_txt_files[0]}"
  sha_txt="$(tr -d '\r\n\t ' < "$sha_txt_path")"
  if [[ "$sha_txt" != "$sha_actual" ]]; then
    echo "ERROR: sha mismatch for $sha_txt_path (txt=$sha_txt actual=$sha_actual)" >&2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  exit 1
fi

echo "ok: release server.json mcpb shas are consistent"

