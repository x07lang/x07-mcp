# verified_core_pure_auth_core_v1

This project is the `x07-mcp` formal-verification dogfood target for
`verified_core_pure_v1`.

It exercises a proof-friendly wrapper around the published
`ext-mcp-auth-core` package, but it is now a developer/demo example rather than
an accepted strong-profile certification example.

The example tracks the current verified-core schema line
(`x07.x07ast@0.8.0`, `x07.arch.manifest@0.3.0`,
`x07.project@0.4.0`, `x07.trust.profile@0.4.0`,
`x07.trust.certificate@0.6.0`) and remains a pure verified-core example, not a
sandboxed trusted-program example.

Current scope:

- the reviewed entry is a small verified-core wrapper over the published bearer parser
- strong prove mode rejects the imported bearer-parser path with `X07V_IMPORTED_STUB_FORBIDDEN`
- `x07 verify --prove --allow-imported-stubs` models that imported parser through the trusted primitive catalog as a developer-only workflow
- smoke and PBT still exercise the real published parser behavior directly
- `x07 trust certify` is expected to reject the strong-profile claim because the proof step refuses imported-stub assumptions

Hydrate the lockfile dependencies first:

```bash
cd docs/examples/verified_core_pure_auth_core_v1
x07 pkg lock --project x07.json
```

Run the profile check:

```bash
x07 trust profile check \
  --project x07.json \
  --profile arch/trust/profiles/verified_core_pure_v1.json \
  --entry auth_core_cert.main_v1
```

Run the smoke + PBT suite:

```bash
x07 test --all --manifest tests/tests.json
```

Show the strong prove rejection explicitly:

```bash
x07 verify --prove \
  --project x07.json \
  --entry auth_core_cert.main_v1
```

That command should fail with `X07V_IMPORTED_STUB_FORBIDDEN`.

Run the developer prove flow:

```bash
x07 verify --prove \
  --allow-imported-stubs \
  --emit-proof target/auth_core.proof.json \
  --project x07.json \
  --entry auth_core_cert.main_v1

x07 prove check --proof target/auth_core.proof.json
```

Show the strong-profile rejection explicitly:

```bash
x07 trust certify \
  --project x07.json \
  --profile arch/trust/profiles/verified_core_pure_v1.json \
  --entry auth_core_cert.main_v1 \
  --out-dir target/cert
```

That command should fail; in the current toolchain the rejection report includes
`X07TC_EPROVE_UNSUPPORTED` because the strong prove step refuses
imported-stub assumptions. The repo CI keeps this example as a
negative-certification check so the developer-only bearer-parser path cannot
quietly turn into an accepted strong certificate.
