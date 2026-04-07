# Postgres demo: expected Hardproof findings

This page documents what you should see when running the canonical Postgres demo flow:

```sh
cd demos/postgres-public-beta
./scripts/run_demo.sh --deps-only
./scripts/run_demo.sh --server
./scripts/verify_demo.sh
```

## Expected output files

The demo writes the Hardproof scan artifacts under:

- `demos/postgres-public-beta/out/scan/scan.json` (schema `x07.mcp.scan.report@0.4.0`)
- `demos/postgres-public-beta/out/scan/scan.events.jsonl` (scan progress/event stream)

## Expected scan shape (local demo)

For the default demo target (`http://127.0.0.1:8403/mcp`) the scan report includes five dimensions:

- `conformance`
- `reliability`
- `performance`
- `security`
- `trust`

And a token/context usage overlay under `usage_metrics`.

Because the demo flow passes `--server-json` and `--mcpb`, the expected top-level score shape is:

- `score_truth_status = "publishable"`
- `score_available = true`
- `overall_score` is an integer
- `partial_score` is `null`
- `unknown_dimensions = []`

If you intentionally rerun the same target without trust inputs, the expected shape changes:

- `score_truth_status = "partial"`
- `overall_score = null`
- `partial_score` is populated
- `gating_reasons` includes `TRUST-UNKNOWN`

If the demo starts failing or producing new findings unexpectedly, treat it as a regression and
inspect `findings[]` in `scan.json` for finding codes and evidence.

To get a human-readable summary from an existing report file:

```sh
hardproof report summary --input demos/postgres-public-beta/out/scan/scan.json
```

To understand a specific finding code:

```sh
hardproof explain <FINDING_CODE>
```
