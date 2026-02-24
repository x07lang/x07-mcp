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

## Local deps mode (workspace layout)

Some checks run in `X07_MCP_LOCAL_DEPS=1` mode and expect an `x07/` checkout at `../x07` relative to the `x07-mcp/` repo root (matching the `x07lang/` workspace layout).
