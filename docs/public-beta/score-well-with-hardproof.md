# Score well with Hardproof (x07-native servers)

Hardproof `scan` emits a single report (`scan.json`) with five dimension results plus a token/context usage overlay.
This page summarizes how to keep x07-native servers scoring high without turning your server into a “demo-only” artifact.

The current score contract now distinguishes between a publishable full score and a partial score:

- `overall_score` is only present when `score_truth_status = "publishable"`
- `partial_score` is used when the scan is still useful but not publishable yet
- `gating_reasons` and `unknown_dimensions` explain what is still missing

## Conformance

- Keep MCP protocol semantics correct and deterministic (initialize, tools/list, tools/call, error envelopes).
- Prefer stable ordering and stable JSON shapes for identical inputs.
- Keep the expected-failures baseline tiny; delete entries as soon as the bug is fixed.

## Reliability

Reliability checks focus on “same request → same response” stability.

- Make `ping` deterministic.
- Make unknown-method and error envelopes deterministic (stable code/message/data shape).
- Avoid time/randomness in protocol-level responses.

## Performance

Performance checks are intentionally simple and CI-friendly.

- Keep cold-start and `tools/list` fast.
- Ensure the server can handle a small burst of concurrent requests without errors.

## Security

Security checks focus on common MCP failure modes that enable tool poisoning or request confusion.

- Make `tools/list` stable across repeated calls (no drift).
- For non-local HTTP targets, validate `Host`/`Origin` (defend against DNS rebinding patterns).
- Prefer HTTPS for non-local targets.

## Trust

Trust checks are enabled when a scan is given `--server-json` (and optionally `--mcpb`).

- Ensure `server.json` includes registry publisher metadata under `_meta`.
- Ensure the `.mcpb` sha256 matches `server.json.packages[].fileSha256`.
- If you want a publishable overall score in CI, provide both trust inputs and gate with `hardproof ci --require-trust-for-full-score`.

## Token/context usage overlay (agent-friendly servers)

Hardproof estimates token footprints for common MCP surfaces. To keep usage healthy:

- Keep `tools/list` small: fewer tools, shorter descriptions, fewer long examples.
- Keep input schemas small: remove redundant fields; avoid large enums or deeply nested objects when not needed.
- Keep responses small: return only required fields; paginate results; return only necessary fields.

The scan report includes the overlay under `usage_metrics`, plus `USAGE-*` findings when thresholds are exceeded.
Useful top-level usage checks now include `tool_count` and `metadata_to_payload_ratio_pct`, in addition to the existing
catalog/schema/response token estimates.
