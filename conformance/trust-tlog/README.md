# Trust Tlog Conformance

Phase-16 trust transparency monitor scenarios.

Scenarios:
- `publish16/trust_tlog_monitor_ok`
- `publish16/trust_tlog_monitor_unexpected`
- `publish16/trust_tlog_monitor_inconsistent`

Run:

```sh
./conformance/trust-tlog/run.sh
```

This wrapper executes `scripts/conformance/run_trust_tlog_scenarios.sh` and validates each scenario against `baselines/*.json`.
