# trusted_program_sandboxed_local_stdio_v1

This project is the `x07-mcp` sandboxed trusted-program dogfood target built
from the stdio router/worker template.

It keeps the same stdio server shape as the template, but upgrades the project
to the current trust surface:

- async stdio router entry under `run-os-sandboxed`
- dedicated certifiable async entry `certify.main_v1`
- dedicated certified capsule boundary for the worker/tool implementation
- `x07.arch.manifest@0.3.0` + boundary index + capsule index/contract
- `x07.trust.profile@0.2.0` posture for `trusted_program_sandboxed_local_v1`
- checked-in capsule attestation snapshot

Current scope:

- `router.main_v1` is the operational stdio server entry
- `certify.main_v1` is the proof-friendly async certification entry for the
  pre-capsule payload path
- `worker.main_v1` is the certified capsule boundary used by the router
- `x07 test` exercises router config, worker conformance, and a sandboxed worker
  smoke that emits runtime-attestation evidence into the test report
- capsule attestation is fully checkable today

The design split is intentional: the async proof target stays inside the
current certifiable subset, while the real worker capsule and sandbox runtime
surface are still pinned by capsule attestations plus the sandbox smoke tests.

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

Run the stdio smoke:

```bash
python3 tests/stdio_bundle_smoke.py
```

Both the bundle smoke and the sandboxed `x07 test` entry require a supported
`run-os-sandboxed` backend. In CI this example runs on a self-hosted runner
with that backend available.

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
  --entry certify.main_v1 \
  --out-dir target/cert
```

If you only want the locally portable checks, run:

```bash
x07 test --manifest tests/tests.portable.json --filter portable/router_contract --exact
x07 test --manifest tests/tests.portable.json --filter portable/certify_echo --exact
x07 test --manifest tests/tests.portable.json --filter portable/worker_echo --exact
```

Run the profile and capsule checks:

```bash
x07 trust profile check \
  --project x07.json \
  --profile arch/trust/profiles/trusted_program_sandboxed_local_v1.json \
  --entry certify.main_v1

x07 trust capsule check \
  --project x07.json \
  --index arch/capsules/index.x07capsule.json
```

Re-emit the capsule attestation snapshot:

```bash
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
`docs/examples/trusted_program_sandboxed_local_stdio_v1/arch/capsules/capsule.stdio_worker.attest.json`.
The repo CI runs the full certificate path on a supported self-hosted VM runner.
