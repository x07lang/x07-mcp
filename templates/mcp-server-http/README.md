# MCP Server (HTTP) — Template

This template scaffolds a minimal MCP **HTTP** server in X07 with a router/worker split:

- **Router**: HTTP transport + lifecycle + JSON-RPC dispatch
- **Worker**: one `tools/call` execution under `run-os-sandboxed`

## Layout

- `config/mcp.server.json`: server config (`x07.mcp.server_config@0.3.0`, default `auth.mode="oauth2"`)
- `config/mcp.server.dev.json`: no-auth dev config (`auth.mode="none"`)
- `config/mcp.tools.json`: tools manifest (`x07.mcp.tools_manifest@0.2.0`)
- `config/mcp.oauth.json`: OAuth config (`x07.mcp.oauth@0.2.0`, `jwt_jwks_v1` + optional DPoP nonce + signed PRM)
- `config/auth/`: runtime auth secrets generated during `x07-mcp scaffold init`
- `config/fixtures/auth/`: JWKS + test JWT/DPoP fixtures used by `jwt_jwks_v1`
- `tests/config/auth/`: deterministic auth fixture secrets used by template tests
- `trust/bundles/dev_trust_bundle_v1.trust_bundle.json`: trust bundle for PRM signer pins
- `trust/bundles/dev_trust_bundle_v1.trust_bundle.sig.jwt`: signed trust bundle statement
- `trust/frameworks/dev_local_trust_framework_v1.trust_framework.json`: resource policy + bundle composition + bundle publisher pins
- `trust/trust.lock.json`: deterministic lock pins for trust bundle/signature digests
- `trust/registry/v1/metadata/*`: TUF-lite root/timestamp/snapshot metadata fixtures
- `trust/registry/v1/transparency/checkpoint.jwt`: witness checkpoint fixture
- `trust/state.json`: anti-rollback state seed
- `publish/prm.json`: signed PRM fixture used by publish dry-run validation
- `publish/server.json`: sample generated `server.json` with publisher trust summary
- `fixtures/oauth/prm.multi_as.json`: multi-AS PRM fixture for policy-governed issuer selection
- `src/main.x07.json`: router entry
- `src/worker_main.x07.json`: worker entry
- `src/mcp/user.x07.json`: dispatch shim for user tools
- `src/tools/hello.x07.json`: demo tools (`hello.echo`, `hello.work`, `hello.bump_resource`)
- `tests/`: smoke, compile-import, and HTTP replay fixtures

## Included Phase-4 demos

- `hello.echo`: simple typed echo tool.
- `hello.work`: emits `notifications/progress` and checks cancellation.
- `hello.bump_resource`: emits `notifications/resources/updated` for `hello://greeting`.
- `config/mcp.resources.json` includes `hello://greeting` for subscribe/read demos.

## Quickstart

Dependencies are already declared in `x07.json`. If you need to refresh lock/deps:

```sh
x07 pkg lock --project x07.json
```

Bundle router + worker:

```sh
x07 bundle --project x07.json --profile os --out out/mcp-router
x07 bundle --project x07.json --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
```

Run the router (HTTP endpoint):

```sh
./out/mcp-router
```

The MCP endpoint is `http://127.0.0.1:8314/mcp` in the default config.

For no-auth local dev:

```sh
X07_MCP_CFG_PATH=config/mcp.server.dev.json ./out/mcp-router
```

For the default `jwt_jwks_v1` auth profile, use the bundled fixtures:

- Bearer JWT: `config/fixtures/auth/access_token_rs256_valid.jwt`
- DPoP-bound JWT: `config/fixtures/auth/access_token_rs256_dpop.jwt`
- DPoP proofs (per-request): `config/fixtures/auth/dpop_proof_valid_init.jwt`, `config/fixtures/auth/dpop_proof_valid_call.jwt`

Phase 10 adds:

- DPoP nonce hardening (RFC9449) exercised by RR test `mcp/http/replay/hello_dpop_nonce`
- `signed_metadata` in PRM responses (RFC9728) asserted by RR test `mcp/http/replay/golden_prm_signed_200`

Phase 13 adds:

- signed trust bundle verification pinned by trust framework publishers
- trust lock digest verification (`trust/trust.lock.json`)
- governed multi-AS PRM selection (`prefer_order_v1`)

Phase 15 adds:

- TUF-lite registry metadata fixtures (`root.json`, `timestamp.jwt`, `snapshot.jwt`)
- witness checkpoint fixture (`transparency/checkpoint.jwt`)
- anti-rollback trust-pack metadata emitted in publish summary (`minSnapshotVersion`, `snapshotSha256`, `checkpointSha256`)
- replay fixtures for successful and rollback metadata fetch flows (`trust.tuf_ok`, `trust.tuf_rollback_timestamp`)

OAuth Protected Resource Metadata (RFC9728) is served at:

* Insertion URL: `http://127.0.0.1:8314/.well-known/oauth-protected-resource/mcp`
* Root alias (when `serve_root_alias=true`): `http://127.0.0.1:8314/.well-known/oauth-protected-resource`

Run tests:

```sh
x07 test --manifest tests/tests.json
```

Validate publish trust policy:

```sh
x07-mcp registry gen \
  --in x07.mcp.json \
  --out publish/server.json \
  --mcpb out/template-http.mcpb
x07-mcp publish --dry-run --server-json publish/server.json --mcpb out/template-http.mcpb
```
