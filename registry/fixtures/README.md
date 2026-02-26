# Registry Fixtures

Fixtures provide deterministic `x07.mcp.json -> server.json` examples for CI.

- `input.x07.mcp.json` is the source manifest passed to `x07-mcp registry gen`.
- `expected.server.json` is the exact canonical output expected from generation.
- `trust/` contains trust-summary validation fixtures:
  - `server.json.fixture.valid.json`: valid publisher `_meta` trust summary.
  - `server.json.fixture.too_large_meta.json`: oversized `_meta` fixture (must fail).
  - `publish_meta_summary.fixture.json`: expected generated trust summary payload.
