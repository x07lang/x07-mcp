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
