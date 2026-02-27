# OAuth config (`x07.mcp.oauth@0.2.0`)

The HTTP templates use an OAuth config file (usually `mcp.oauth.json` or `config/mcp.oauth.json`) when `auth.mode="oauth2"`.

## Schema

```jsonc
{
  "schema_version": "x07.mcp.oauth@0.2.0",

  // Resource identifier (full MCP URL, including `/mcp`)
  "resource": "http://127.0.0.1:8314/mcp",

  // Serve RFC9728 “root alias” endpoint when true
  "serve_root_alias": true,

  // RFC9728: authorization servers for this protected resource
  "authorization_servers": ["https://auth.example.com"],

  // Server-advertised scopes (used in PRM + WWW-Authenticate `scope=...`)
  "scopes_supported": ["mcp:tools", "mcp:tasks"],

  // Current supported bearer methods
  "bearer_methods_supported": ["header"],

  // RFC9728: advertise DPoP support / requirements in PRM (optional)
  "dpop_signing_alg_values_supported": ["ES256"],
  "dpop_bound_access_tokens_required": false,

  "validation": {
    "kind": "test_static" | "introspection_v1" | "jwt_jwks_v1",

    "static_tokens": [
      { "token": "TOKEN", "sub": "dev-user", "scope": "mcp:tools mcp:tasks" }
    ],

    "introspection": {
      "url": "https://issuer.example.com/oauth2/introspect",
      "auth": {
        "mode": "client_secret_basic",
        "client_id": "…",
        "client_secret": "…"
      },
      "timeout_ms": 1200,
      "retry": { "max_attempts": 2, "backoff_ms": 0 },
      "require_audience": true,
      "audience": ["http://127.0.0.1:8314/mcp"],
      "cache": { "enabled": true, "ttl_ms": 5000 }
    },

    "jwt_jwks_v1": {
      "issuer": "https://auth.example.com",
      "audiences": ["http://127.0.0.1:8314/mcp"],
      "clock_skew_s": 180,

      // Optional: deterministic tests / RR (defaults to OS time)
      "clock": { "kind": "fixed_v1", "now_s": 1700000005 },

      "accepted_algs": ["RS256"],
      "jwks_source": {
        "kind": "file",
        "path": "config/fixtures/auth/jwks.json"

        // Or:
        // "kind": "url",
        // "url": "https://issuer.example.com/.well-known/jwks.json",
        // "timeout_ms": 2000,
        // "ssrf_guard": "strict_v1"
      },

      // Optional: accept DPoP proofs and enforce binding rules.
      "dpop": {
        "enabled": true,
        "required": false,
        "accepted_algs": ["ES256"],
        "replay_window_s": 300
      }
    }
  },

  // RFC9449: Resource server-provided DPoP nonce (optional hardening)
  "dpop_nonce_v1": {
    // "disabled" (default) or "required"
    "mode": "disabled",

    // Validity window for issued nonces
    "ttl_s": 60,

    // When true, success responses may include a fresh DPoP-Nonce
    "rotate_on_success": true,

    // HMAC secret used to issue/verify nonces
    "secret_b64_file": "config/auth/dpop_nonce.secret.b64",

    // Current supported binding mode: "jkt"
    "bind_to": "jkt",

    // Test-only determinism override (guarded by CI release checks)
    "test_fixed_nonce": "test-nonce-0001"
  },

  // RFC9728: include signed_metadata JWT in PRM responses (legacy HS256; optional)
  "prm_signed_v1": {
    "enabled": true,
    "alg": "HS256",
    "iss": "https://auth.example.com",
    "ttl_s": 3600,
    "secret_b64_file": "config/auth/prm_signed.secret.b64",
    "include_iat_exp": true
  },

  // RFC9728: include signed_metadata JWT in PRM responses (asymmetric; optional)
  // Mutually exclusive with prm_signed_v1.
  "prm_signing_v2": {
    "enabled": true,
    "cfg_path": "config/auth/prm_signing.v2.json"
  }
}
```

## DPoP nonce behavior (RFC9449)

When `dpop_nonce_v1.mode="required"` and the request is authenticated via DPoP, the server enforces a nonce in the DPoP proof (`nonce` claim).

On nonce errors, the HTTP transport responds with:

- `401`
- `WWW-Authenticate: DPoP error="use_dpop_nonce", ...`
- `DPoP-Nonce: <nonce>`
- `Cache-Control: no-store`
- an `application/json` body with `{ "error": "use_dpop_nonce", "error_description": "..." }`

If your server is used from browsers, ensure the HTTP transport CORS config exposes `DPoP-Nonce` (and typically `WWW-Authenticate`) via `Access-Control-Expose-Headers`.

## Signed PRM behavior (RFC9728)

When PRM signing is enabled, PRM responses additionally include `signed_metadata` (a JWT). Consumers that validate it should merge signed claims into the PRM JSON, with signed claims taking precedence.

`x07-mcp` supports two signing modes:

- `prm_signed_v1` (legacy): HS256 with a shared secret.
- `prm_signing_v2`: asymmetric signing (Ed25519/RS256) using a private JWK + issuer trust anchors for verification.

The template uses `prm_signing_v2`.

## PRM signing v2 (`x07.mcp.prm_signing@0.2.0`)

`prm_signing_v2.cfg_path` points to a separate config file used to issue `signed_metadata` for PRM responses.

Example (Ed25519):

```jsonc
{
  "schema_version": "x07.mcp.prm_signing@0.2.0",
  "enabled": true,
  "alg": "Ed25519",
  "kid": "prm-ed25519-2026-01",
  "iss": "http://127.0.0.1:8314/mcp",
  "keypair_jwk_path": "./config/auth/prm_signing.ed25519.current.jwk.json",
  "claims_include": [
    "resource",
    "authorization_servers",
    "scopes_supported",
    "bearer_methods_supported",
    "dpop_signing_alg_values_supported",
    "dpop_bound_access_tokens_required"
  ],
  "include_iat_exp": true,
  "ttl_s": 3600
}
```

## PRM verification config (`x07.mcp.prm_verify@0.2.0`) and trust anchors (`x07.mcp.trust_anchors@0.1.0`)

Clients that validate `signed_metadata` use a PRM verify config plus an explicit trust-anchor file:

- `trust_anchors_path`: pinned issuers + keys (supports rollover windows)
- `mode="fail_closed"` + `require_signed_metadata=true`: reject unsigned PRM with error code `PRM_SIGNED_METADATA_REQUIRED`

The HTTP template ships a sample trust anchor file at `config/auth/prm_trust_anchors.json`.

## Publish trust framework (`x07.mcp.trust.framework@0.2.0`) + trust lock (`x07.mcp.trust.lock@0.1.0`)

Phase 13 extends publish-time trust policy with signed trust bundles, trust lock pinning, and governed authorization-server selection:

- `auth.prm.trust_framework.path`: trust framework used by runtime PRM trust decisions.
- `auth.prm.trust_framework.trust_lock_path`: optional trust lock used to pin bundle/signature digests.
- `publish.require_signed_prm=true`: unsigned PRM is rejected during publish dry-run.
- `publish.trust_framework.path`: trust framework used to resolve issuer allowlist + pinned keys.
- `publish.trust_framework.trust_lock_path`: trust lock used during publish-time verification.
- `publish.trust_framework.emit_meta_summary=true`: injects publisher `_meta` trust summary under `io.modelcontextprotocol.registry/publisher-provided.x07`:
  - `trustFrameworkSha256`
  - `trustLockSha256`
  - `requireSignedPrm`
  - `asSelectionStrategy`

When framework bundles set `require_signature=true`, publish/runtime verification requires:

- compact JWS statement (`*.trust_bundle.sig.jwt`)
- publisher issuer + key (`kid`) pinned in `bundle_publishers`
- valid `iat/exp` window and `bundle_sha256` claim binding

Reference files:

- `trust/bundles/dev_trust_bundle_v1.trust_bundle.json`
- `trust/bundles/dev_trust_bundle_v1.trust_bundle.sig.jwt`
- `trust/frameworks/dev_local_trust_framework_v1.trust_framework.json`
- `trust/trust.lock.json`
- `publish/prm.json`

## PRM endpoints (RFC9728)

Given `resource = http://127.0.0.1:8314/mcp`, the PRM endpoints are:

- **Insertion URL**: `http://127.0.0.1:8314/.well-known/oauth-protected-resource/mcp`
- **Root alias** (only when `serve_root_alias=true`): `http://127.0.0.1:8314/.well-known/oauth-protected-resource`

The PRM JSON response includes `resource` matching the configured `resource`, plus `authorization_servers`.
