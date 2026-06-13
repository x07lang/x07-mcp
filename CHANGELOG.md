# Changelog

## Unreleased

- x07-mcp CLI implemented in X07 (bundled via `x07 bundle`).
- `x07lang-mcp` extended to a pack-gated `0.2.0` surface with ecosystem, package, wasm, web-ui, device, app, and platform tools.
- `ext-mcp-toolkit@0.3.8`, `ext-mcp-transport-stdio@0.3.7`, `ext-mcp-transport-http@0.3.18`, `ext-mcp-rr@0.3.17`, and `ext-mcp-sandbox@0.3.11` add runtime descriptor loading and pack-oriented sandbox/limits support.
- `ext-mcp-toolkit@0.3.9` fixes stdio `initialize` negotiation so MCP clients using `2025-03-26` or `2025-06-18` can start successfully against `2025-11-25` servers.
- `ext-mcp-toolkit@0.3.10`, `ext-mcp-sandbox@0.3.12`, `ext-mcp-transport-stdio@0.3.8`, and `ext-mcp-transport-http@0.3.19` republish the current runtime-descriptor and stdio-negotiation bytes under fresh immutable versions, and CI now checks patched project locks against a clean registry-only graph before the local-deps guard.
- `ext-mcp-transport-http@0.3.20` fixes the HTTP session follow-up crash in the per-client inflight limiter and refreshes all repo-owned HTTP MCP server templates/locks to that package line.
- `ext-mcp-auth@0.4.7`, `ext-mcp-transport-http@0.3.21`, `ext-mcp-rr@0.3.19`, `ext-mcp-trust-os@0.5.1`, and `x07-mcp@0.4.3` move the active MCP kit to `ext-net@0.1.10` under fresh immutable package versions.
- Docs retell the X07 story: X07 leads as the deterministic, certifiable execution substrate for agent-written software, and this repo is the MCP-facing entry point to it.
- `x07lang-mcp`: the web-ui (`x07.web_ui.*`), device (`x07.device.*`), app (`x07.app.*`), and platform (`lp.*`) packs were removed in the 2026-06 refocus, when their backing repos (`x07-web-ui`, `x07-device-host`, `x07-platform*`) were archived and made read-only on GitHub.
- `x07lang-mcp@0.2.10`: `x07.doc_v1` docs and tool description surface the behavioral `summary` field that `x07 doc` export rows carry on x07 0.2.11+.
- `x07lang-mcp@0.2.10`: toolchain pins move from x07 v0.2.3 to v0.2.11 (repo `x07-toolchain.toml` and CI `X07_TOOLCHAIN_TAG`), so the server is developed and conformance-tested against the latest toolchain.
- `x07lang-mcp@0.2.10`: docs note that the lossless x07text projection (`x07 ast to-text` / `x07 ast from-text`, x07 0.2.11+) is available through `x07.exec_v1` until a dedicated tool ships; both subcommands emit `{ok,in,out,sha256}` reports.

## 0.1.0

- Initial release of `ext-mcp-*` packages and stdio server template.
