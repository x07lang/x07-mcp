# Publish dry-run

Use dry-run validation before pushing artifacts to any registry.

## 1) Generate `server.json`

```sh
x07-mcp registry gen \
  --in servers/postgres-mcp/x07.mcp.json \
  --out servers/postgres-mcp/dist/server.json \
  --mcpb servers/postgres-mcp/dist/postgres-mcp.mcpb
```

## 2) Validate artifact + hash

```sh
x07-mcp publish --dry-run \
  --server-json servers/postgres-mcp/dist/server.json \
  --mcpb servers/postgres-mcp/dist/postgres-mcp.mcpb
```

Dry-run checks schema validity, `_meta` limits, package hash integrity, and trust-policy enforcement when `publish.require_signed_prm=true`:

- `signed_metadata` is required in PRM
- signer issuer must match `resource_policies.allowed_prm_signers`
- signer key must exist in trust bundles
- signed trust bundles must verify against framework-pinned bundle publisher keys
- trust bundle + signature digests must match `trust/trust.lock.json` pins
- `_meta.io.modelcontextprotocol.registry/publisher-provided.x07` must match generated trust summary

## Trust Framework Artifacts

The HTTP template includes:

- `trust/bundles/dev_trust_bundle_v1.trust_bundle.json`
- `trust/bundles/dev_trust_bundle_v1.trust_bundle.sig.jwt`
- `trust/frameworks/dev_local_trust_framework_v1.trust_framework.json`
- `trust/trust.lock.json`
- `publish/prm.json`
- `publish/server.json` (publisher trust summary with `trustFrameworkSha256` + `trustLockSha256`)

Release tags are guarded against placeholder hashes by `registry/scripts/release_metadata_guard.sh`.
