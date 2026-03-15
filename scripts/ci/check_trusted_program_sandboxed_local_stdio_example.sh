#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

example_dir="docs/examples/trusted_program_sandboxed_local_stdio_v1"
project_json="x07.json"
profile_json="arch/trust/profiles/trusted_program_sandboxed_local_v1.json"
tests_json="tests/tests.json"
capsule_index_json="arch/capsules/index.x07capsule.json"
capsule_contract_json="arch/capsules/capsule.stdio_worker.contract.json"
capsule_attest_json="arch/capsules/capsule.stdio_worker.attest.json"
capsule_conformance_json="arch/capsules/capsule.stdio_worker.conformance.json"

./scripts/ci/hydrate_project_deps.sh "${example_dir}/x07.json"
cd "${example_dir}"

x07 arch check --manifest arch/manifest.x07arch.json --json=off >/dev/null
x07 trust profile check \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry certify.main_v1 \
  >/dev/null

mkdir -p target
x07 test --all --manifest "${tests_json}" --report-out target/tests.report.json >/dev/null

jq -e '
  .tests
  | map(select(.id == "sandbox/worker_echo_attested"))
  | length == 1
' target/tests.report.json >/dev/null

jq -e '
  .tests[]
  | select(.id == "sandbox/worker_echo_attested")
  | .run.runtime_attestation.path
  | strings
  | length > 0
' target/tests.report.json >/dev/null

python3 tests/stdio_bundle_smoke.py >/dev/null

mkdir -p target/capsules
x07 trust capsule attest \
  --contract "${capsule_contract_json}" \
  --module src/worker.x07.json \
  --module src/worker_main.x07.json \
  --module src/mcp/user.x07.json \
  --lockfile x07.lock.json \
  --conformance-report "${capsule_conformance_json}" \
  --out target/capsules/capsule.stdio_worker.attest.json \
  >/dev/null

if ! cmp -s target/capsules/capsule.stdio_worker.attest.json "${capsule_attest_json}"; then
  diff -u "${capsule_attest_json}" target/capsules/capsule.stdio_worker.attest.json
  exit 1
fi

x07 trust capsule check --project "${project_json}" --index "${capsule_index_json}" >/dev/null

mkdir -p target/cert
x07 trust certify \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry certify.main_v1 \
  --out-dir target/cert \
  >/dev/null

test -f target/cert/certificate.json

jq -e '
  .verdict == "accepted"
  and .profile == "trusted_program_sandboxed_local_v1"
  and (.async_proof.covered | tonumber) >= 1
  and (.evidence.runtime_attestation.path | strings | length > 0)
  and ((.evidence.capsule_attestations | length) >= 1)
' target/cert/certificate.json >/dev/null
