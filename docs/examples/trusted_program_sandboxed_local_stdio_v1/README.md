# trusted_program_sandboxed_local_stdio_v1

This project is the `x07-mcp` sandboxed trusted-program dogfood target built
from the stdio router/worker template.

It keeps the same stdio server shape as the template, but upgrades the project
to the current trust surface:

- `x07.x07ast@0.8.0` on the mutable source surface
- `x07.project@0.4.0` with `project.operational_entry_symbol = "router.main_v1"`
- async stdio router entry under `run-os-sandboxed`
- dedicated certified capsule boundaries for the stdio router and worker/tool implementation
- `x07.arch.manifest@0.3.0` + boundary index + capsule index/contract
- `x07.trust.profile@0.4.0` posture for `trusted_program_sandboxed_local_v1`
- checked-in capsule attestation snapshots

Current scope:

- `router.main_v1` is both the operational stdio server entry and the
  certification target for the strong profile
- `certify.main_v1` remains only as a developer helper path; the strong profile
  rejects it as a surrogate certification entry
- `router.main_v1` is covered by a checked router capsule attestation
- `worker.main_v1` is the certified capsule boundary used by the router
- `x07 test` exercises router config, worker conformance, and a sandboxed worker
  smoke that emits runtime-attestation evidence into the test report
- capsule attestations are fully checkable today

The important change is that the certificate is now about the shipped stdio
router itself, not a proof-friendly surrogate. The repo CI re-checks the
tracked router/worker capsule attestations and verifies that a surrogate-entry
mutation is rejected.

This example is the no-network baseline. The companion HTTP example at
`../trusted_program_sandboxed_net_http_v1/` demonstrates the networked
certification line with peer-policy and dependency-closure evidence.

Certificate execution requires a supported `run-os-sandboxed` VM backend. On a
host without that backend, keep to the static trust/capsule checks plus the
portable non-sandbox smoke coverage.

Hydrate the lockfile dependencies first:

```bash
cd docs/examples/trusted_program_sandboxed_local_stdio_v1
x07 pkg lock --project x07.json
```

Bundle the sandboxed router and worker:

```bash
x07 bundle --profile sandbox_router --out out/mcp-router
x07 bundle --profile sandbox_worker --program src/worker_main.x07.json --out out/mcp-worker
```

Run the stdio smoke on a supported VM backend:

```bash
python3 tests/stdio_bundle_smoke.py
```

If you only have the Docker guest image handy for local smoke work, you can
still launch the bundle with:

```bash
X07_VM_BACKEND=docker \
X07_VM_GUEST_IMAGE=x07-guest-runner:vm-smoke \
X07_I_ACCEPT_WEAKER_ISOLATION=1 \
python3 tests/stdio_bundle_smoke.py
```

That weaker-isolation path is only for launch/smoke debugging. The strong
profile still requires a supported VM backend without weaker isolation.

Run the project tests:

```bash
x07 test --all --manifest tests/tests.json
```

`tests/tests.json` is the certification manifest: every entry is expected to run
under `run-os-sandboxed` and to contribute evidence that `x07 trust certify`
can bind into the certificate.

Emit the sandboxed certificate bundle on a supported VM host:

```bash
x07 trust certify \
  --project x07.json \
  --profile arch/trust/profiles/trusted_program_sandboxed_local_v1.json \
  --entry router.main_v1 \
  --out-dir target/cert
```

If you only want the locally portable checks, run:

```bash
x07 test --manifest tests/tests.portable.json --filter portable/router_contract --exact
x07 test --manifest tests/tests.portable.json --filter portable/developer_certify_echo --exact
x07 test --manifest tests/tests.portable.json --filter portable/worker_echo --exact
```

Run the profile and capsule checks:

```bash
x07 trust profile check \
  --project x07.json \
  --profile arch/trust/profiles/trusted_program_sandboxed_local_v1.json \
  --entry router.main_v1

x07 trust capsule check \
  --project x07.json \
  --index arch/capsules/index.x07capsule.json
```

Re-emit the capsule attestation snapshot:

```bash
x07 trust capsule attest \
  --contract arch/capsules/capsule.stdio_router.contract.json \
  --module src/main.x07.json \
  --module src/router.x07.json \
  --lockfile x07.lock.json \
  --conformance-report arch/capsules/capsule.stdio_router.conformance.json \
  --out arch/capsules/capsule.stdio_router.attest.json

x07 trust capsule attest \
  --contract arch/capsules/capsule.stdio_worker.contract.json \
  --module src/worker.x07.json \
  --module src/worker_main.x07.json \
  --module src/mcp/user.x07.json \
  --lockfile x07.lock.json \
  --conformance-report arch/capsules/capsule.stdio_worker.conformance.json \
  --out arch/capsules/capsule.stdio_worker.attest.json
```

The tracked capsule evidence lives at
`docs/examples/trusted_program_sandboxed_local_stdio_v1/arch/capsules/capsule.stdio_router.attest.json`
and
`docs/examples/trusted_program_sandboxed_local_stdio_v1/arch/capsules/capsule.stdio_worker.attest.json`.
The repo CI runs the full certificate path on a supported self-hosted VM runner,
re-checks both capsule attestation snapshots, and asserts that the old
`certify.main_v1` surrogate path is rejected under the strong profile.
