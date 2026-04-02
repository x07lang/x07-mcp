# Flagship MCP server shortlist

Focus is a small set of flagship reference servers that represent the strongest “real user” paths for the MCP kit.

## Public hero path

**Postgres** is the current public hero path.

Work should optimize for one end-to-end demo that a new external user can reproduce. Postgres is the server we will polish for that path.

## Deferred flagships

- Kubernetes
- GitHub

## Why these were shortlisted

- They cover the highest-leverage integration surfaces (data, infra, and code).
- They represent common enterprise and developer workflows.
- They exercise the important transport + auth + sandbox + conformance paths without spreading effort across many unrelated APIs.

## What this means for other reference servers

The other reference servers remain valuable as reference inventory, but they are not current hero paths.
Work should not try to “polish everything” across the full server list.
