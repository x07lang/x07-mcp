# Trust Tlog Monitor

The trust tlog monitor adds append-only trust transparency checks (checkpoint verification, consistency proof verification, and policy evaluation of newly appended entries).

## Run package monitor tests

```sh
cd packages/ext/x07-ext-mcp-trust-os/0.5.2
x07 test --manifest tests/tests.json
```

```sh
cd packages/app/x07-mcp/0.4.4
x07 test --manifest tests/tests.json
```

## Run trust-tlog conformance scenarios

```sh
./conformance/trust-tlog/run.sh
```

The wrapper resolves the pinned local `x07` checkout (`$X07_ROOT`, `./x07`, or `../x07`) and stages `deps/x07/libx07_ext_fs.*` with `./scripts/build_ext_fs.sh` when that native backend is missing, so the standalone trust-tlog gate matches the scheduled CI workflow.

The conformance wrapper validates these scenarios against baselines:

- `publish16/trust_tlog_monitor_ok`
- `publish16/trust_tlog_monitor_unexpected`
- `publish16/trust_tlog_monitor_inconsistent`

## Fixtures and replay assets

- Template dataset: `templates/trust-registry-tlog/`
- HTTP RR sessions: `rr/http/trust_tlog_monitor_*.http.jsonl`
