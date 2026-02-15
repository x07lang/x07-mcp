# Sandbox policy & limits

Tool execution runs under `run-os-sandboxed` and is configured by a per-tool allowlist under the tool’s `x07` block in `config/mcp.tools.json`.

## Policy env model

The router compiles the tool allowlist into `X07_OS_*` environment variables passed to the worker process (filesystem, network, environment).

Bundled worker executables always force sandboxing on (`X07_WORLD=run-os-sandboxed`, `X07_OS_SANDBOXED=1`). Other `X07_OS_*` settings may be overridden by the router for tool-specific policies.

## Limits profiles

Tools may select a `limits_profile` (for example: `mcp_tool_fast_v1`, `mcp_tool_standard_v1`, `mcp_tool_expensive_v1`) to control per-invocation caps like timeout and stdout/stderr limits.

## Budget profiles

Tool execution is also wrapped in a budget scope. The budget profile is selected from `x07.limits_profile` and loaded from `arch/budgets/profiles/<PROFILE_ID>.budget.json` at build time.
