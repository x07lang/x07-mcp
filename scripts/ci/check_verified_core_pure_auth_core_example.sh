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
mkdir -p target
prove_reject_out="target/auth_core_strong_prove_reject.json"
if x07 verify \
  --prove \
  --project "${project_json}" \
  --entry auth_core_cert.main_v1 \
  >"${prove_reject_out}"; then
  echo "expected strong prove mode to reject imported-stub assumptions" >&2
  exit 1
fi

python3 - "${prove_reject_out}" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
codes = {
    diag.get("code")
    for diag in report.get("diagnostics", [])
    if isinstance(diag, dict)
}
if "X07V_IMPORTED_STUB_FORBIDDEN" not in codes:
    print(
        "missing X07V_IMPORTED_STUB_FORBIDDEN rejection diagnostic for auth-core prove flow",
        file=sys.stderr,
    )
    sys.exit(1)
PY

proof_path="target/auth_core.proof.json"
x07 verify \
  --prove \
  --allow-imported-stubs \
  --emit-proof "${proof_path}" \
  --project "${project_json}" \
  --entry auth_core_cert.main_v1 \
  >/dev/null
x07 prove check --proof "${proof_path}" >/dev/null

rm -rf target/cert
reject_out="target/auth_core_strong_reject.json"
if x07 trust certify \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry auth_core_cert.main_v1 \
  --out-dir "target/cert" \
  >"${reject_out}"; then
  echo "expected strong certification to reject developer-only imported stub assumptions" >&2
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
if "X07TC_EPROVE_UNSUPPORTED" not in codes:
    print(
        "missing X07TC_EPROVE_UNSUPPORTED rejection diagnostic for auth-core example",
        file=sys.stderr,
    )
    sys.exit(1)
PY
