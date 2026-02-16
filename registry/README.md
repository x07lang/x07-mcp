# Registry Pipeline

This directory contains the pinned MCP registry schema, deterministic fixtures,
and helper scripts used by `x07-mcp` registry workflows.

## Layout

- `schema/` vendored `server.json` schema pin.
- `fixtures/` deterministic input/output examples for generator checks.
- `scripts/` helpers for local and CI validation.

## Commands

- Generate registry output from a manifest:
  - `x07-mcp registry gen --in <x07.mcp.json> --out <server.json>`
- Validate a package payload before publish:
  - `x07-mcp publish --dry-run --server-json <server.json> --mcpb <file>`
