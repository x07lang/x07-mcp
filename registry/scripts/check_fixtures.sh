#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

mkdir -p .agent_cache/registry-fixtures

./scripts/ci/hydrate_root_deps.sh

if [[ ! -x dist/x07-mcp ]]; then
  x07 bundle \
    --project x07.json \
    --profile os \
    --out dist/x07-mcp \
    --json=off
fi

for fixture in registry/fixtures/*; do
  [[ -d "${fixture}" ]] || continue
  input="${fixture}/input.x07.mcp.json"
  expected="${fixture}/expected.server.json"
  actual=".agent_cache/registry-fixtures/$(basename "${fixture}").server.json"
  rm -f "${actual}"

  ./dist/x07-mcp registry gen \
    --in "${input}" \
    --out "${actual}" \
    --schema registry/schema/server.schema.2025-12-11.json \
    --machine json \
    >/dev/null

  if ! diff -u "${expected}" "${actual}"; then
    echo "fixture mismatch: $(basename "${fixture}")" >&2
    exit 1
  fi
done

echo "ok: registry fixtures are stable"
