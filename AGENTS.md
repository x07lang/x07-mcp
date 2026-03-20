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

## CI failure mode: missing patch dependency paths

Symptom: jobs fail in dependency hydration with `X07PKG_PATCH_MISSING_DEP` (for example `ext-u64-rs@0.1.4` in root `x07.json`, or `ext-net@0.1.10` in `conformance/client-x07/x07.json`).

Mitigation implemented:

- `x07 pkg lock` hydrates patch paths under `.x07/deps/...` during lock hydration (no separate materialize step).
- `scripts/ci/materialize_patch_deps.sh` pre-populates patch paths for jobs that run from a clean checkout without workspace-local `.x07/deps`.
- `scripts/ci/hydrate_root_deps.sh` and `scripts/ci/hydrate_project_deps.sh` retry `x07 pkg lock --check` to handle transient registry/network failures.

## Local deps mode (workspace layout)

Some checks run in `X07_MCP_LOCAL_DEPS=1` mode and expect an `x07/` checkout at `../x07` relative to the `x07-mcp/` repo root (matching the `x07lang/` workspace layout).
