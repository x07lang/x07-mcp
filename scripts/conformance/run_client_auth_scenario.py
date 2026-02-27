#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def _load_json(path: Path) -> dict:
    doc = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(doc, dict):
        raise ValueError(f"expected object json: {path}")
    return doc


def _run_phase13_multi_as(scenario_dir: Path) -> int:
    sys.path.insert(0, str(Path("registry/scripts").resolve()))
    from registry_lib import resolve_as_policy, select_authorization_server_v1

    prm = _load_json(scenario_dir / "inputs/prm.multi_as.json")
    framework = _load_json(scenario_dir / "inputs/trust_framework.json")
    expected = _load_json(scenario_dir / "expected/decision.json")

    resource = prm.get("resource")
    if not isinstance(resource, str) or not resource:
        raise ValueError("inputs/prm.multi_as.json missing resource")

    auth_servers = prm.get("authorization_servers")
    if not isinstance(auth_servers, list) or not all(isinstance(x, str) for x in auth_servers):
        raise ValueError("inputs/prm.multi_as.json missing authorization_servers[]")

    as_policy = resolve_as_policy(framework, resource)
    if as_policy is None:
        raise ValueError("trust framework has no authorization_server_policy for resource")

    got = select_authorization_server_v1(as_policy, auth_servers)

    if got.get("selected_issuer") != expected.get("selected_issuer"):
        raise RuntimeError(
            f"selected_issuer mismatch: got={got.get('selected_issuer')!r} want={expected.get('selected_issuer')!r}"
        )

    got_rejected = got.get("rejected")
    want_rejected = expected.get("rejected")
    if got_rejected != want_rejected:
        raise RuntimeError(f"rejected mismatch: got={got_rejected!r} want={want_rejected!r}")

    rr_protocol = scenario_dir / "rr/protocol.jsonl"
    rr_audit = scenario_dir / "rr/audit.jsonl"
    if not rr_protocol.is_file() or not rr_audit.is_file():
        raise RuntimeError("scenario rr fixtures missing")

    return 0


def _run_phase11_signed_required_missing(scenario: str, client: Path) -> int:
    cmd = [
        sys.executable,
        "conformance/client-auth/run_scenario.py",
        "--scenario",
        scenario,
        "--client",
        str(client),
    ]
    proc = subprocess.run(cmd, check=False)
    return proc.returncode


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", required=True)
    ap.add_argument("--client", default="dist/x07-mcp-conformance-client")
    ap.add_argument("--scenarios-root", default="conformance/client-auth/scenarios")
    args = ap.parse_args(argv)

    scenario_dir = Path(args.scenarios_root) / args.scenario
    if not scenario_dir.is_dir():
        raise FileNotFoundError(f"missing scenario dir: {scenario_dir}")

    if (scenario_dir / "inputs/prm.multi_as.json").is_file() and (scenario_dir / "inputs/trust_framework.json").is_file():
        return _run_phase13_multi_as(scenario_dir)

    return _run_phase11_signed_required_missing(args.scenario, Path(args.client))


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)
