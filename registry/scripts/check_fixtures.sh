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
  if [[ ! -f "${input}" || ! -f "${expected}" ]]; then
    continue
  fi
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

python3 - <<'PY'
from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, "registry/scripts")
from registry_lib import _build_publish_meta_summary, read_json, validate_non_schema_constraints

root = pathlib.Path(".")
trust_dir = root / "registry" / "fixtures" / "trust"

valid_path = trust_dir / "server.json.fixture.valid.json"
too_large_path = trust_dir / "server.json.fixture.too_large_meta.json"
summary_path = trust_dir / "publish_meta_summary.fixture.json"

for p in (valid_path, too_large_path, summary_path):
    if not p.is_file():
        raise SystemExit(f"missing trust fixture: {p}")

valid_doc = read_json(valid_path)
if not isinstance(valid_doc, dict):
    raise SystemExit(f"fixture must be object: {valid_path}")
validate_non_schema_constraints(valid_doc)

too_large_doc = read_json(too_large_path)
if not isinstance(too_large_doc, dict):
    raise SystemExit(f"fixture must be object: {too_large_path}")
try:
    validate_non_schema_constraints(too_large_doc)
except ValueError as exc:
    if "4096" not in str(exc):
        raise SystemExit(f"unexpected error for oversized fixture: {exc}") from exc
else:
    raise SystemExit("expected oversized trust _meta fixture to fail")

expected_summary = read_json(summary_path)
if not isinstance(expected_summary, dict):
    raise SystemExit(f"fixture must be object: {summary_path}")

got_summary = _build_publish_meta_summary(
    require_signed=True,
    resource_metadata_path="/.well-known/oauth-protected-resource",
    signer_iss="https://auth.example.com",
    framework_sha256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
)

if json.dumps(expected_summary, sort_keys=True, separators=(",", ":")) != json.dumps(
    got_summary, sort_keys=True, separators=(",", ":")
):
    raise SystemExit("publish_meta_summary fixture drift")
PY

echo "ok: registry fixtures are stable"
