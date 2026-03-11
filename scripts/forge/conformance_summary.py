#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from common import REPO_ROOT, emit, emit_error, read_json, utc_now_iso


def _status_counts(checks: list[dict[str, Any]]) -> tuple[int, int, dict[str, int], str]:
    success = 0
    failure = 0
    other: dict[str, int] = {}
    latest = ""
    for check in checks:
        status = str(check.get("status", "UNKNOWN"))
        if status == "SUCCESS":
            success += 1
        elif status in {"FAILURE", "ERROR"}:
            failure += 1
        else:
            other[status] = other.get(status, 0) + 1
        timestamp = check.get("timestamp")
        if isinstance(timestamp, str) and timestamp > latest:
            latest = timestamp
    return success, failure, other, latest


def _nested_checks(results_dir: Path) -> dict[str, Path]:
    latest: dict[str, Path] = {}
    for path in results_dir.glob("*/*/checks.json"):
        scenario = path.parent.parent.name
        current = latest.get(scenario)
        if current is None or path.stat().st_mtime > current.stat().st_mtime:
            latest[scenario] = path
    return latest


def _top_level_checks(results_dir: Path) -> list[Path]:
    return sorted(results_dir.glob("checks-*.json"), key=lambda path: path.stat().st_mtime, reverse=True)


def _build_summary(results_dir: Path, baseline: str | None) -> dict[str, Any]:
    scenario_paths = _nested_checks(results_dir)
    scenarios: list[dict[str, Any]] = []
    total_checks = 0
    total_success = 0
    total_failure = 0

    if scenario_paths:
        for scenario in sorted(scenario_paths):
            path = scenario_paths[scenario]
            raw = read_json(path)
            checks = raw if isinstance(raw, list) else []
            success, failure, other, latest = _status_counts([item for item in checks if isinstance(item, dict)])
            scenarios.append(
                {
                    "id": scenario,
                    "check_file": str(path),
                    "check_count": len(checks),
                    "success_count": success,
                    "failure_count": failure,
                    "other_status_counts": other,
                    "passed": failure == 0 and not other,
                    "latest_timestamp": latest,
                }
            )
            total_checks += len(checks)
            total_success += success
            total_failure += failure
    else:
        for idx, path in enumerate(_top_level_checks(results_dir)[:1]):
            raw = read_json(path)
            checks = raw if isinstance(raw, list) else []
            success, failure, other, latest = _status_counts([item for item in checks if isinstance(item, dict)])
            scenarios.append(
                {
                    "id": f"adhoc-{idx + 1}",
                    "check_file": str(path),
                    "check_count": len(checks),
                    "success_count": success,
                    "failure_count": failure,
                    "other_status_counts": other,
                    "passed": failure == 0 and not other,
                    "latest_timestamp": latest,
                }
            )
            total_checks += len(checks)
            total_success += success
            total_failure += failure

    passing_scenarios = sum(1 for item in scenarios if item["passed"])
    return {
        "schema_version": "x07.mcp.conformance.summary@0.1.0",
        "generated_at": utc_now_iso(),
        "results_dir": str(results_dir),
        "baseline_path": baseline or "",
        "scenario_count": len(scenarios),
        "passing_scenarios": passing_scenarios,
        "failing_scenarios": len(scenarios) - passing_scenarios,
        "total_checks": total_checks,
        "success_count": total_success,
        "failure_count": total_failure,
        "ok": len(scenarios) > 0 and total_failure == 0,
        "scenarios": scenarios,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize x07-mcp conformance results")
    parser.add_argument("--results-dir", default=str(REPO_ROOT / "conformance" / "results"))
    parser.add_argument("--baseline")
    parser.add_argument("--machine", choices=["json"], default=None)
    parser.add_argument("--out")
    args = parser.parse_args()

    results_dir = Path(args.results_dir).resolve()
    if not results_dir.is_dir():
        return emit_error(
            f"missing --results-dir: {results_dir}",
            out=args.out,
            group="conformance",
            name="summary",
            machine=args.machine,
        )

    try:
        doc = _build_summary(results_dir, args.baseline)
        return emit(doc, out=args.out, group="conformance", name="summary", machine=args.machine)
    except Exception as exc:
        return emit_error(
            str(exc),
            out=args.out,
            group="conformance",
            name="summary",
            machine=args.machine,
        )


if __name__ == "__main__":
    raise SystemExit(main())
