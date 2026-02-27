# Trust Policy Registry (local fixtures)

This directory contains a static registry layout used by replay tests.
In production, host the same structure behind HTTPS (for example, internal NGINX).

Phase 15 adds TUF-lite metadata fixtures under `v1/metadata/` plus an optional witness
checkpoint under `v1/transparency/`:

- `metadata/root.json`
- `metadata/timestamp.jwt`
- `metadata/snapshot.jwt`
- `transparency/checkpoint.jwt`

The runtime never trusts on first use: remote content is pinned by `trust.lock.json`,
validated against registry metadata, and checked against local anti-rollback state.
