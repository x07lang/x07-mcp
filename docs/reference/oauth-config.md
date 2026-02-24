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

  // RFC9728: include signed_metadata JWT in PRM responses (optional)
  "prm_signed_v1": {
    "enabled": true,
    "alg": "HS256",
    "iss": "https://auth.example.com",
    "ttl_s": 3600,
    "secret_b64_file": "config/auth/prm_signed.secret.b64",
    "include_iat_exp": true
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

When `prm_signed_v1.enabled=true`, PRM responses additionally include `signed_metadata` (a JWT). Consumers that validate it should merge signed claims into the PRM JSON, with signed claims taking precedence.

## PRM endpoints (RFC9728)

Given `resource = http://127.0.0.1:8314/mcp`, the PRM endpoints are:

- **Insertion URL**: `http://127.0.0.1:8314/.well-known/oauth-protected-resource/mcp`
- **Root alias** (only when `serve_root_alias=true`): `http://127.0.0.1:8314/.well-known/oauth-protected-resource`

The PRM JSON response includes `resource` matching the configured `resource`, plus `authorization_servers`.
