# Trust Tlog Monitor

Phase-16 adds append-only trust transparency checks (checkpoint verification, consistency proof verification, and policy evaluation of newly appended entries).

## Run package monitor tests

```sh
cd packages/ext/x07-ext-mcp-trust-os/0.5.0
x07 test --manifest tests/tests.json
```

```sh
cd packages/app/x07-mcp/0.4.0
x07 test --manifest tests/tests.json
```

## Run trust-tlog conformance scenarios

```sh
./conformance/trust-tlog/run.sh
```

The conformance wrapper validates these scenarios against baselines:

- `publish16/trust_tlog_monitor_ok`
- `publish16/trust_tlog_monitor_unexpected`
- `publish16/trust_tlog_monitor_inconsistent`

## Fixtures and replay assets

- Template dataset: `templates/trust-registry-tlog/`
- HTTP RR sessions: `rr/http/trust_tlog_monitor_*.http.jsonl`
