# Mock Authorization Server (dev/test only)

This is a tiny local OAuth helper for development and template tests.

It only implements a token introspection endpoint at:

POST http://127.0.0.1:8799/oauth2/introspect

It recognizes these tokens:

- `devtoken-mcp-tools` => active=true, scope="mcp:tools", aud="http://127.0.0.1:8314/mcp"
- anything else        => active=false

This is **not** a real authorization server. Replace it in production.

