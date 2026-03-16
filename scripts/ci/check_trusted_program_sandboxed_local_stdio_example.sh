#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

example_dir="docs/examples/trusted_program_sandboxed_local_stdio_v1"
project_json="x07.json"
profile_json="arch/trust/profiles/trusted_program_sandboxed_local_v1.json"
tests_json="tests/tests.json"
capsule_index_json="arch/capsules/index.x07capsule.json"
router_capsule_contract_json="arch/capsules/capsule.stdio_router.contract.json"
router_capsule_attest_json="arch/capsules/capsule.stdio_router.attest.json"
router_capsule_conformance_json="arch/capsules/capsule.stdio_router.conformance.json"
capsule_contract_json="arch/capsules/capsule.stdio_worker.contract.json"
capsule_attest_json="arch/capsules/capsule.stdio_worker.attest.json"
capsule_conformance_json="arch/capsules/capsule.stdio_worker.conformance.json"
operational_entry="router.main_v1"
surrogate_entry="certify.main_v1"

./scripts/ci/hydrate_project_deps.sh "${example_dir}/x07.json"
cd "${example_dir}"

x07 arch check --manifest arch/manifest.x07arch.json --write-lock --json=off >/dev/null
x07 trust profile check \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry "${operational_entry}" \
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
  --contract "${router_capsule_contract_json}" \
  --module src/main.x07.json \
  --module src/router.x07.json \
  --lockfile x07.lock.json \
  --conformance-report "${router_capsule_conformance_json}" \
  --out target/capsules/capsule.stdio_router.attest.json \
  >/dev/null

if ! cmp -s target/capsules/capsule.stdio_router.attest.json "${router_capsule_attest_json}"; then
  diff -u "${router_capsule_attest_json}" target/capsules/capsule.stdio_router.attest.json
  exit 1
fi

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
  --entry "${operational_entry}" \
  --out-dir target/cert \
  >/dev/null

test -f target/cert/certificate.json

jq -e '
  .verdict == "accepted"
  and .profile == "trusted_program_sandboxed_local_v1"
  and .operational_entry_symbol == "router.main_v1"
  and (.async_proof.proved | tonumber) == (.async_proof.reachable | tonumber)
  and (.evidence.runtime_attestation.path | strings | length > 0)
  and ((.evidence.capsule_attestations | length) >= 2)
  and ((.evidence.effect_logs | length) >= 2)
  and ([.proof_inventory[] | (.proof_object.path | strings | length > 0) and (.proof_check_report.path | strings | length > 0)] | all)
' target/cert/certificate.json >/dev/null

jq -r '.proof_inventory[].proof_object.path' target/cert/certificate.json \
  | while IFS= read -r proof_path; do
      [[ -n "${proof_path}" ]] || continue
      x07 prove check --proof "${proof_path}" >/dev/null
    done

case "$(uname -s)" in
  Darwin)
    surrogate_dir="$(mktemp -d -t x07_stdio_surrogate)"
    ;;
  *)
    surrogate_dir="$(mktemp -d)"
    ;;
esac
cleanup() { rm -rf "${surrogate_dir}" || true; }
trap cleanup EXIT

cp -R . "${surrogate_dir}/example"
python3 - "${surrogate_dir}/example/x07.json" "${surrogate_entry}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["certification_entry_symbol"] = sys.argv[2]
path.write_text(json.dumps(doc, indent=2) + "\n")
PY

reject_out="${surrogate_dir}/surrogate.reject.json"
if (
  cd "${surrogate_dir}/example" && x07 trust certify \
    --project "${project_json}" \
    --profile "${profile_json}" \
    --entry "${operational_entry}" \
    --out-dir target/surrogate-cert \
    >"${reject_out}"
); then
  echo "expected surrogate certification entry to be rejected under the strong profile" >&2
  exit 1
fi

python3 - "${reject_out}" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
codes = {
    diag.get("code")
    for diag in report.get("diagnostics", [])
    if isinstance(diag, dict)
}
if "X07TC_ESURROGATE_ENTRY_FORBIDDEN" not in codes:
    print(
        "missing X07TC_ESURROGATE_ENTRY_FORBIDDEN rejection diagnostic for surrogate stdio certification",
        file=sys.stderr,
    )
    sys.exit(1)
PY
