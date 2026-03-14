#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

example_dir="docs/examples/verified_core_pure_auth_core_v1"
project_json="x07.json"
profile_json="arch/trust/profiles/verified_core_pure_v1.json"
manifest_json="arch/manifest.x07arch.json"
tests_json="tests/tests.json"

./scripts/ci/hydrate_project_deps.sh "${example_dir}/x07.json"
cd "${example_dir}"

x07 arch check --manifest "${manifest_json}" --json=off >/dev/null
x07 trust profile check \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry auth_core_cert.main_v1 \
  >/dev/null
x07 test --all --manifest "${tests_json}" >/dev/null
x07 verify --prove --project "${project_json}" --entry auth_core_cert.main_v1 >/dev/null
rm -rf "target/cert"
x07 trust certify \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry auth_core_cert.main_v1 \
  --out-dir "target/cert" \
  >/dev/null
