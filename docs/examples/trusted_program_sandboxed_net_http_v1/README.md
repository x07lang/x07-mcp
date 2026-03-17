# trusted_program_sandboxed_net_http_v1

This project is the `x07-mcp` sandboxed networked HTTP router/worker developer
example built from the HTTP router/worker template.

It keeps the public network/capsule surfaces current, but it is not the repo's
release-gated strong-profile dogfood target. Use
`../trusted_program_sandboxed_local_stdio_v1/` for the strong-profile example.

Current scope:

- `router.main_v1` is the operational HTTP server entry under `run-os-sandboxed`
- `certify.main_v1` remains a local developer helper, not the strong claim
- certified worker capsule and certified HTTP router capsule
- pinned loopback peer-policy and tracked capsule attestation snapshots
- dependency-closure evidence and runtime-attested sandbox tests
- the public certificate review flow is the same as the stdio example:
  `formal_verification_scope`, `entry_body_formally_proved`,
  `operational_entry_proof_inventory_refs`, and accepted proof-check reports in
  `proof_inventory`

Run the static posture checks:

```bash
cd docs/examples/trusted_program_sandboxed_net_http_v1
x07 pkg lock --project x07.json

x07 trust profile check \
  --project x07.json \
  --profile arch/trust/profiles/trusted_program_sandboxed_net_v1.json \
  --entry router.main_v1

x07 trust capsule check \
  --project x07.json \
  --index arch/capsules/index.x07capsule.json

x07 pkg attest-closure \
  --project x07.json \
  --out target/dep-closure.attest.json
```

Bundle the sandboxed router and worker:

```bash
x07 bundle --profile sandbox_router --out out/mcp-router
x07 bundle --profile sandbox_worker --program src/worker_main.x07.json --out out/mcp-worker
```

Smoke the loopback HTTP router:

```bash
X07_MCP_CFG_PATH=config/mcp.server.json out/mcp-router &
router_pid=$!
trap 'kill "$router_pid"' EXIT
python3 ../../../scripts/forge/mcp_inspect.py \
  tool-call \
  --transport http \
  --url http://127.0.0.1:8314/mcp \
  --name echo \
  --args-json '{"text":"hello from inspect"}' \
  --out target/http.inspect.json \
  --machine json
```

Run the sandboxed tests on a host with a supported VM backend:

```bash
x07 test --all --manifest tests/tests.json
```

If you certify the example on a supported VM host, review
`target/cert/certificate.json` through the same public fields as the stdio
example instead of inferring proof coverage from the presence of capsule
attestations alone.

If you only want the locally portable checks, run:

```bash
x07 test --manifest tests/tests.portable.json --filter portable/router_contract --exact
x07 test --manifest tests/tests.portable.json --filter portable/developer_certify_echo --exact
x07 test --manifest tests/tests.portable.json --filter portable/worker_echo --exact
```

Re-emit the tracked capsule attestation snapshots:

```bash
x07 trust capsule attest \
  --contract arch/capsules/capsule.http_router.contract.json \
  --module src/main.x07.json \
  --module src/router.x07.json \
  --lockfile x07.lock.json \
  --conformance-report arch/capsules/capsule.http_router.conformance.json \
  --out arch/capsules/capsule.http_router.attest.json

x07 trust capsule attest \
  --contract arch/capsules/capsule.stdio_worker.contract.json \
  --module src/worker.x07.json \
  --module src/worker_main.x07.json \
  --module src/mcp/user.x07.json \
  --lockfile x07.lock.json \
  --conformance-report arch/capsules/capsule.stdio_worker.conformance.json \
  --out arch/capsules/capsule.stdio_worker.attest.json
```
