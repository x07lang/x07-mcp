# x07-mcp — Agent Notes

## CI flake: pinned toolchain download

Symptom: GitHub Actions jobs fail in the step named `Install X07 (pinned)` (curl/tar errors). This tends to show up more often when the workflow fans out (for example `publish-dry-run` matrix).

Mitigation implemented:

- `.github/workflows/ci.yml` caches `~/.x07` keyed by `X07_TOOLCHAIN_TAG`.
- `.github/workflows/ci.yml` installs via `scripts/ci/install_x07_toolchain.sh`, which retries downloads and validates the tarball before extracting.

If this flares up again:

- Verify `X07_TOOLCHAIN_TAG` and `X07_TOOLCHAIN_TARBALL_LINUX_X64` match a real GitHub release asset in `x07lang/x07`.
- Re-run the workflow; if it persists, increase `X07_MCP_CURL_RETRIES` / `X07_MCP_CURL_RETRY_DELAY_SECS` in the workflow env.

## CI flake: conformance client dependency hydration

Symptom: `ci / conformance-client / auth` fails in `Build conformance client` (usually while running `x07 pkg lock --check`), due to transient registry/network failures.

Mitigation implemented:

- `.github/workflows/ci.yml` runs `scripts/ci/hydrate_project_deps.sh conformance/client-x07/x07.json` (retry loop) before bundling the conformance client.

## CI failure mode: patched project lock drift

Symptom: jobs that validate checked-in template/server locks fail with `X07PKG_LOCK_MISMATCH` after local patch package contents change under an already-published version (for example `templates/mcp-server-http/x07.lock.json` after `ext-mcp-sandbox@0.3.12` or `ext-mcp-toolkit@0.3.10` work is copied into a stale versioned package directory).

Mitigation implemented:

- `.github/workflows/ci.yml` keeps the strict `scripts/ci/hydrate_project_deps.sh` check in `template-mcp-server-http-tests`, so GitHub still rejects stale checked-in locks.
- `scripts/ci/check_all.sh` now runs a clean temp-copy `x07 pkg lock --check` across all checked-in patched projects under `conformance/`, `templates/`, and `servers/`, so the committed locks must match the registry-resolved graph without any local `x07-mcp/packages` fallback.
- `scripts/ci/check_all.sh` still runs the `materialize_patch_deps.sh` + `x07 pkg lock --check` flow afterward, with sibling `../x07` fallback disabled, and now clears each project-local `.x07/deps` cache first so stale hydrated packages cannot create false lock drift locally.

## CI failure mode: x07lang-mcp bundle smoke misses workspace-local deps

Symptom: `ci / check` fails in `x07lang-mcp release smoke` or `tests/published_bundle_smoke.py` because `servers/_shared/ci/install_server_deps.sh` falls back to registry hydration even though the workflow checked out `../x07`.

Mitigation implemented:

- `servers/x07lang-mcp/tests/stdio_smoke_lib.py` now enables `X07_MCP_LOCAL_DEPS=1` whenever the sibling `../x07` source checkout exists; it no longer requires a built `../x07/target/debug/x07`.
- `.github/workflows/ci.yml` also sets `X07_MCP_LOCAL_DEPS=1` explicitly for the `Stdio and installed-bundle smoke` step, so the bundle smoke uses the same local-deps mode as `scripts/ci/check_all.sh`.
- `scripts/ci/check_all.sh` now runs `servers/_shared/ci/install_server_deps.sh servers/x07lang-mcp` before the long package/scaffold lanes, so stale `servers/x07lang-mcp/x07.lock.json` drift fails fast instead of waiting for the final `x07lang-mcp release smoke`.
- `servers/_shared/ci/install_server_deps.sh` now forwards `x07 pkg lock --check` mismatch output to stderr, so callers that silence stdout still show the real `X07PKG_LOCK_MISMATCH` cause.
- Local helpers now reject a sibling `../x07` checkout unless it is a clean checkout of the exact pinned tag from `x07-toolchain.toml`; use `X07_ROOT` to point checks at a matching worktree when the main sibling checkout is ahead.

## CI failure mode: missing patch dependency paths

Symptom: jobs fail in dependency hydration with `X07PKG_PATCH_MISSING_DEP` (for example `ext-u64-rs@0.1.4` in root `x07.json`, or `ext-net@0.1.10` in `conformance/client-x07/x07.json`).

Mitigation implemented:

- `x07 pkg lock` hydrates patch paths under `.x07/deps/...` during lock hydration (no separate materialize step).
- `scripts/ci/materialize_patch_deps.sh` pre-populates patch paths for jobs that run from a clean checkout without workspace-local `.x07/deps`.
- `scripts/ci/hydrate_root_deps.sh` and `scripts/ci/hydrate_project_deps.sh` retry `x07 pkg lock --check` to handle transient registry/network failures.

## Local deps mode (workspace layout)

Some checks run in `X07_MCP_LOCAL_DEPS=1` mode and expect an `x07/` checkout at `../x07` relative to the `x07-mcp/` repo root (matching the `x07lang/` workspace layout).
