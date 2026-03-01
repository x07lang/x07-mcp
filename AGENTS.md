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

## CI failure mode: missing patch dependency paths

Symptom: jobs fail in dependency hydration with `X07PKG_PATCH_MISSING_DEP` (for example `ext-u64-rs@0.1.4` in root `x07.json`, or `ext-net@0.1.9` in `conformance/client-x07/x07.json`).

Mitigation implemented:

- `x07 pkg lock` hydrates patch paths under `.x07/deps/...` during lock hydration (no separate materialize step).
- `scripts/ci/hydrate_root_deps.sh` and `scripts/ci/hydrate_project_deps.sh` retry `x07 pkg lock --check` to handle transient registry/network failures.

## Local deps mode (workspace layout)

Some checks run in `X07_MCP_LOCAL_DEPS=1` mode and expect an `x07/` checkout at `../x07` relative to the `x07-mcp/` repo root (matching the `x07lang/` workspace layout).
