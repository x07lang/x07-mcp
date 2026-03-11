#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path
from typing import Any

from common import REPO_ROOT, emit, emit_error, read_json, utc_now_iso


def _load_json_if_exists(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    data = read_json(path)
    return data if isinstance(data, dict) else None


def _default_x07_root() -> Path:
    env_value = os.environ.get("X07_ROOT", "")
    if env_value:
        return Path(env_value).resolve()
    return (REPO_ROOT.parent / "x07").resolve()


def _build_summary(server_dir: Path, *, monitor: dict[str, Any] | None = None) -> dict[str, Any]:
    manifest_path = server_dir / "x07.mcp.json"
    manifest = _load_json_if_exists(manifest_path) or {}
    publish = manifest.get("publish", {})
    trust_framework = publish.get("trust_framework", {}) if isinstance(publish, dict) else {}
    prm = publish.get("prm", {}) if isinstance(publish, dict) else {}

    trust_framework_path = server_dir / str(trust_framework.get("path", ""))
    trust_lock_path = server_dir / str(trust_framework.get("trust_lock_path", ""))
    prm_path = server_dir / str(prm.get("path", ""))
    meta_summary_path = server_dir / "publish" / "meta_summary.json"
    registry_manifest_path = server_dir / "publish" / "server.mcp-registry.json"
    trust_pack = trust_framework.get("trust_pack", {}) if isinstance(trust_framework, dict) else {}

    meta_summary = _load_json_if_exists(meta_summary_path)
    registry_manifest = _load_json_if_exists(registry_manifest_path)
    healthy = all(
        [
            bool(manifest),
            manifest_path.is_file(),
            isinstance(publish, dict),
            not publish.get("require_signed_prm") or prm_path.is_file(),
            not trust_framework or trust_framework_path.is_file(),
            not trust_framework or trust_lock_path.is_file(),
        ]
    )
    if monitor is not None and not monitor.get("passed", False):
        healthy = False

    return {
        "schema_version": "x07.mcp.trust.summary@0.1.0",
        "generated_at": utc_now_iso(),
        "server": {
            "id": server_dir.name,
            "path": str(server_dir),
            "identifier": manifest.get("identifier", ""),
            "display_name": manifest.get("display_name", ""),
            "version": manifest.get("version", ""),
        },
        "status": {
            "healthy": healthy,
            "has_manifest": manifest_path.is_file(),
            "has_prm": prm_path.is_file(),
            "has_trust_framework": trust_framework_path.is_file(),
            "has_trust_lock": trust_lock_path.is_file(),
            "has_meta_summary": meta_summary_path.is_file(),
            "has_registry_manifest": registry_manifest_path.is_file(),
        },
        "publish": {
            "require_signed_prm": bool(publish.get("require_signed_prm", False)) if isinstance(publish, dict) else False,
            "prm_path": str(prm_path) if prm_path.is_file() else "",
            "trust_framework_path": str(trust_framework_path) if trust_framework_path.is_file() else "",
            "trust_lock_path": str(trust_lock_path) if trust_lock_path.is_file() else "",
            "emit_meta_summary": bool(trust_framework.get("emit_meta_summary", False)) if isinstance(trust_framework, dict) else False,
            "trust_pack": trust_pack if isinstance(trust_pack, dict) else {},
        },
        "artifacts": {
            "manifest_path": str(manifest_path) if manifest_path.is_file() else "",
            "meta_summary_path": str(meta_summary_path) if meta_summary_path.is_file() else "",
            "registry_manifest_path": str(registry_manifest_path) if registry_manifest_path.is_file() else "",
        },
        "meta_summary": meta_summary or {},
        "registry_manifest": {
            "schema": registry_manifest.get("$schema", "") if registry_manifest else "",
            "version": registry_manifest.get("version", "") if registry_manifest else "",
        },
        "monitor": monitor or {},
    }


def _run_tlog_monitor(x07_root: Path) -> dict[str, Any]:
    script = REPO_ROOT / "scripts" / "conformance" / "run_trust_tlog_scenarios.sh"
    if not script.is_file():
        raise ValueError(f"missing trust monitor script: {script}")
    env = os.environ.copy()
    env["X07_ROOT"] = str(x07_root)
    proc = subprocess.run(
        [str(script)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    baseline_root = REPO_ROOT / "conformance" / "trust-tlog" / "baselines"
    scenarios = []
    for path in sorted(baseline_root.glob("*.json")):
        doc = _load_json_if_exists(path) or {}
        scenarios.append(
            {
                "id": doc.get("id", path.stem),
                "expected_status": doc.get("status", ""),
                "baseline_path": str(path),
            }
        )
    return {
        "ran": True,
        "passed": proc.returncode == 0,
        "x07_root": str(x07_root),
        "exit_code": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "scenario_count": len(scenarios),
        "scenarios": scenarios,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit x07-mcp trust summaries")
    parser.add_argument("trust_subcmd", choices=["summary", "tlog-monitor"])
    parser.add_argument("--server-dir", default=str(REPO_ROOT / "servers" / "x07lang-mcp"))
    parser.add_argument("--x07-root")
    parser.add_argument("--machine", choices=["json"], default=None)
    parser.add_argument("--out")
    args = parser.parse_args()

    server_dir = Path(args.server_dir).resolve()
    if not server_dir.is_dir():
        return emit_error(
            f"missing --server-dir: {server_dir}",
            out=args.out,
            group="trust",
            name=args.trust_subcmd,
            machine=args.machine,
            extra={"subcommand": args.trust_subcmd},
        )

    try:
        monitor = None
        if args.trust_subcmd == "tlog-monitor":
            x07_root = Path(args.x07_root).resolve() if args.x07_root else _default_x07_root()
            monitor = _run_tlog_monitor(x07_root)
        doc = _build_summary(server_dir, monitor=monitor)
        doc["subcommand"] = args.trust_subcmd
        if monitor is not None:
            doc["ok"] = bool(monitor.get("passed", False))
        else:
            doc["ok"] = True
        return emit(doc, out=args.out, group="trust", name=args.trust_subcmd, machine=args.machine)
    except Exception as exc:
        return emit_error(
            str(exc),
            out=args.out,
            group="trust",
            name=args.trust_subcmd,
            machine=args.machine,
            extra={"subcommand": args.trust_subcmd},
        )


if __name__ == "__main__":
    raise SystemExit(main())
