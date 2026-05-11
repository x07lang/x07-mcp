#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

example_dir="docs/examples/verified_core_pure_auth_core_v1"
project_json="x07.json"
profile_json="arch/trust/profiles/verified_core_pure_v1.json"
manifest_json="arch/manifest.x07arch.json"
tests_json="tests/tests.json"

rm -rf "${example_dir}/.x07/deps" "${example_dir}/.x07/artifacts/verify"
./scripts/ci/hydrate_project_deps.sh "${example_dir}/x07.json"
cd "${example_dir}"
rm -rf target

x07 arch check --manifest "${manifest_json}" --json=off >/dev/null
x07 trust profile check \
  --project "${project_json}" \
  --profile "${profile_json}" \
  --entry auth_core_cert.main_v1 \
  >/dev/null
x07 test --all --manifest "${tests_json}" >/dev/null
mkdir -p target
prove_probe_out="target/auth_core_strong_prove_probe.json"
if x07 verify \
  --prove \
  --project "${project_json}" \
  --entry auth_core_cert.main_v1 \
  >"${prove_probe_out}"; then
  python3 - "${prove_probe_out}" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
proof_summary_path = (report.get("artifacts", {}) or {}).get("verify_proof_summary_path")
if not proof_summary_path:
    print("successful prove probe did not emit a proof summary artifact", file=sys.stderr)
    sys.exit(1)
proof_summary = json.loads(pathlib.Path(proof_summary_path).read_text())
assumptions = proof_summary.get("assumptions", [])
if not any(
    isinstance(assumption, dict)
    and assumption.get("kind") == "imported_stub"
    and assumption.get("certifiable") is False
    for assumption in assumptions
):
    print(
        "prove probe must expose a non-certifiable imported_stub assumption",
        file=sys.stderr,
    )
    sys.exit(1)
PY
else
  python3 - "${prove_probe_out}" <<'PY'
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
fi

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
if "X07TC_EDEV_ONLY_ASSUMPTION" not in codes:
    print(
        "missing X07TC_EDEV_ONLY_ASSUMPTION rejection diagnostic for auth-core example",
        file=sys.stderr,
    )
    sys.exit(1)
PY
