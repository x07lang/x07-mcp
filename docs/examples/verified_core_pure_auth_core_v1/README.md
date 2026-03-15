# verified_core_pure_auth_core_v1

This project is the `x07-mcp` formal-verification dogfood target for
`verified_core_pure_v1`.

It certifies a proof-friendly wrapper around the published `ext-mcp-auth-core`
package so the review object is the certificate bundle, not the package source.

The example tracks the current verified-core schema line
(`x07.arch.manifest@0.3.0`, `x07.trust.profile@0.2.0`,
`x07.trust.certificate@0.2.0`) but remains a pure verified-core example, not a
sandboxed trusted-program example.

Current scope:

- the certified entry is a small verified-core wrapper over the published bearer parser
- `x07 verify --prove` models that imported parser through the trusted primitive catalog
- smoke and PBT still exercise the real published parser behavior directly

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

Emit a certificate bundle:

```bash
x07 trust certify \
  --project x07.json \
  --profile arch/trust/profiles/verified_core_pure_v1.json \
  --entry auth_core_cert.main_v1 \
  --out-dir target/cert
```

A tracked reference certificate snapshot is kept at
`docs/examples/verified_core_pure_auth_core_v1/target/cert/certificate.json`.
The rest of `target/cert/` remains generated local output.
