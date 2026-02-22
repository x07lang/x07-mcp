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

  "validation": {
    "kind": "test_static" | "introspection_v1",

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
    }
  }
}
```

## PRM endpoints (RFC9728)

Given `resource = http://127.0.0.1:8314/mcp`, the PRM endpoints are:

- **Insertion URL**: `http://127.0.0.1:8314/.well-known/oauth-protected-resource/mcp`
- **Root alias** (only when `serve_root_alias=true`): `http://127.0.0.1:8314/.well-known/oauth-protected-resource`

The PRM JSON response includes `resource` matching the configured `resource`, plus `authorization_servers`.

