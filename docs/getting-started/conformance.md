# Run conformance

Run server conformance with either `x07 mcp` delegation or `x07-mcp` directly.

## Against an existing server URL

```sh
x07 mcp conformance --url http://127.0.0.1:8080/mcp
```

Equivalent direct call:

```sh
x07-mcp conformance --url http://127.0.0.1:8080/mcp
```

## Spawn a reference server

```sh
x07-mcp conformance \
  --baseline conformance/conformance-baseline.yml \
  --spawn postgres-mcp \
  --mode noauth
```

When `--url` is omitted with `--spawn`, the harness derives `bind_host`, `bind_port`, and `mcp_path` from the spawned server config.

Default run mode executes the Phase-4 regression set:

- `server-initialize`
- `ping`
- `tools-list`
- `tools-call-with-progress`
- `resources-subscribe`
- `resources-unsubscribe`
- `server-sse-multiple-streams`
- `dns-rebinding-protection`

Use `--full-suite` to run the full active conformance suite.

Phase-4 baseline policy: keep `conformance/conformance-baseline.yml` empty unless a temporary known issue must be tracked.

## Client mode (auth suite)

Build the X07 conformance client:

```sh
x07 bundle --project conformance/client-x07/x07.json --profile os --out dist/x07-mcp-conformance-client
```

Run upstream conformance in client mode:

```sh
npx -y @modelcontextprotocol/conformance@0.1.14 client \
  --command "./dist/x07-mcp-conformance-client" \
  --suite auth
```

## Client auth regression scenarios (x07-mcp)

`x07-mcp` also ships small conformance-style regression scenarios that are not part of the upstream suite.

Phase 11 (unsigned PRM must be rejected when fail-closed is enabled):

```sh
./scripts/conformance/run_client_auth_scenario.sh \
  prm-signed-required-missing \
  --client dist/x07-mcp-conformance-client
```

Phase 13 (multi-AS PRM selection must follow trust-policy preference order):

```sh
./scripts/conformance/run_client_auth_scenario.sh \
  prm-multi-as-select-prefer-order \
  --client dist/x07-mcp-conformance-client
```

## Trust tlog monitor scenarios (Phase 16)

Run deterministic trust transparency monitor scenarios:

```sh
./scripts/conformance/run_trust_tlog_scenarios.sh
```
