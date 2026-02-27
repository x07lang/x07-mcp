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
- remote trust bundle sources (`source.kind="url"`) must be fully pinned by lock entries (no TOFU)
- remote lock entries must pin URL + digest pairs (`bundle_url`/`sig_url`, `bundle_sha256`/`sig_sha256`)
- `_meta.io.modelcontextprotocol.registry/publisher-provided.x07` must match generated trust summary
- when trust-pack metadata is configured, `_meta...x07.trustPack` must include:
  - `packVersion`
  - `lockSha256`
  - `minSnapshotVersion` (`>0`)
  - `snapshotSha256` and `checkpointSha256` (non-placeholder)

## Trust Framework Artifacts

The HTTP template includes:

- `trust/bundles/dev_trust_bundle_v1.trust_bundle.json`
- `trust/bundles/dev_trust_bundle_v1.trust_bundle.sig.jwt`
- `trust/frameworks/dev_local_trust_framework_v1.trust_framework.json`
- `trust/trust.lock.json`
- `trust/frameworks/dev_remote_pack.trust_framework.json` (optional remote bundle profile)
- `trust/packs/dev_remote_pack/trust.lock.json` (remote lock v2 pins)
- `trust/registry/v1/...` (offline trust pack registry fixture tree, including TUF-lite metadata + witness checkpoint)
- `trust/state.json` (local anti-rollback state seed)
- `publish/prm.json`
- `publish/server.json` (publisher trust summary with `trustFrameworkSha256`, `trustLockSha256`, and `trustPack` anti-rollback fields when configured)

Release tags are guarded against placeholder hashes by `registry/scripts/release_metadata_guard.sh`.
