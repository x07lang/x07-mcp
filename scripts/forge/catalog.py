#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from common import canonical_json_text, first_heading_and_summary, read_json, rel_to_repo, repo_root, write_json


def _load_json(path: Path) -> dict[str, Any]:
    doc = read_json(path)
    if not isinstance(doc, dict):
        raise ValueError(f"{path} must be a JSON object")
    return doc


def _transports_from_cfg(doc: dict[str, Any], *, include_stdio: bool) -> list[str]:
    transports: list[str] = []
    transport = doc.get("transport")
    if isinstance(transport, dict):
        if transport.get("kind") == "http":
            transports.append("streamable-http")
            if transport.get("sse_enabled"):
                transports.append("streamable-http+sse")
        elif transport.get("kind") == "stdio":
            transports.append("stdio")

    transports_map = doc.get("transports")
    if isinstance(transports_map, dict):
        http_cfg = transports_map.get("http")
        if isinstance(http_cfg, dict) and http_cfg.get("enabled", False):
            transports.append("streamable-http")
            streamable = http_cfg.get("streamable")
            if isinstance(streamable, dict):
                sse = streamable.get("sse")
                if isinstance(sse, dict) and sse.get("enabled", False):
                    transports.append("streamable-http+sse")

    if include_stdio and "stdio" not in transports:
        transports.append("stdio")
    return sorted(set(transports))


def _capabilities_from_cfg(doc: dict[str, Any], *, has_prompts: bool, has_resources: bool) -> dict[str, Any]:
    caps = doc.get("capabilities")
    caps_obj = caps if isinstance(caps, dict) else {}
    tasks = caps_obj.get("tasks")
    return {
        "tools": True,
        "prompts": has_prompts,
        "resources": has_resources,
        "tasks": isinstance(tasks, dict),
    }


def _template_items(root: Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for template_dir in sorted((root / "templates").iterdir(), key=lambda path: path.name):
        if not template_dir.is_dir() or template_dir.name in {"shared", "trust-registry-tlog"}:
            continue

        title, summary = first_heading_and_summary(template_dir / "README.md")
        manifest_path = template_dir / "x07.mcp.json"
        cfg_candidates = [
            template_dir / "mcp.server.dev.json",
            template_dir / "mcp.server.json",
            template_dir / "config/mcp.server.json",
            template_dir / "config/mcp.server.dev.json",
        ]
        cfg_path = next((path for path in cfg_candidates if path.is_file()), None)
        manifest = _load_json(manifest_path) if manifest_path.is_file() else {}
        cfg = _load_json(cfg_path) if cfg_path is not None else {}

        item = {
            "id": template_dir.name,
            "title": title or template_dir.name,
            "summary": summary or str(manifest.get("description", "")),
            "path": rel_to_repo(template_dir),
            "readme_path": rel_to_repo(template_dir / "README.md"),
            "version": str(manifest.get("version") or cfg.get("server", {}).get("version", "")),
            "protocol_version": str(cfg.get("server", {}).get("protocolVersion", "")),
            "identifier": str(manifest.get("identifier", "")),
            "transports": _transports_from_cfg(cfg, include_stdio=True),
            "capabilities": _capabilities_from_cfg(
                cfg,
                has_prompts=(template_dir / "config/mcp.prompts.json").is_file() or (template_dir / "mcp.prompts.json").is_file(),
                has_resources=(template_dir / "config/mcp.resources.json").is_file() or (template_dir / "mcp.resources.json").is_file(),
            ),
            "has_publish_manifest": manifest_path.is_file(),
            "has_publish_bundle_script": (template_dir / "publish/build_mcpb.sh").is_file(),
        }
        items.append(item)
    return items


def _reference_server_items(root: Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for server_dir in sorted((root / "servers").iterdir(), key=lambda path: path.name):
        if not server_dir.is_dir() or server_dir.name == "_shared":
            continue

        manifest = _load_json(server_dir / "x07.mcp.json")
        title, summary = first_heading_and_summary(server_dir / "README.md")
        cfg_candidates = [
            server_dir / "config/mcp.server.dev.json",
            server_dir / "config/mcp.server.json",
            server_dir / "config/mcp.server.http.json",
        ]
        cfg_path = next((path for path in cfg_candidates if path.is_file()), None)
        cfg = _load_json(cfg_path) if cfg_path is not None else {}

        item = {
            "id": server_dir.name,
            "identifier": str(manifest.get("identifier", "")),
            "display_name": str(manifest.get("display_name", "")),
            "version": str(manifest.get("version", "")),
            "title": title or str(manifest.get("display_name", "")) or server_dir.name,
            "summary": summary or str(manifest.get("description", "")),
            "path": rel_to_repo(server_dir),
            "readme_path": rel_to_repo(server_dir / "README.md"),
            "official": bool(manifest.get("_meta", {}).get("io.modelcontextprotocol.registry/publisher-provided", {}).get("x07_official", False)),
            "protocol_version": str(cfg.get("server", {}).get("protocolVersion", "")),
            "transports": _transports_from_cfg(cfg, include_stdio=True),
            "capabilities": _capabilities_from_cfg(
                cfg,
                has_prompts=(server_dir / "config/mcp.prompts.json").is_file(),
                has_resources=(server_dir / "config/mcp.resources.json").is_file(),
            ),
            "publish": {
                "has_manifest": (server_dir / "publish/manifest.json").is_file(),
                "has_registry_manifest": (server_dir / "publish/server.mcp-registry.json").is_file(),
                "has_meta_summary": (server_dir / "publish/meta_summary.json").is_file(),
            },
        }
        items.append(item)
    return items


def _conformance_suite_items(root: Path) -> list[dict[str, Any]]:
    server_default_scenarios = [
        "server-initialize",
        "ping",
        "tools-list",
        "tools-call-with-progress",
        "resources-subscribe",
        "resources-unsubscribe",
        "server-sse-multiple-streams",
        "dns-rebinding-protection",
    ]
    client_auth_scenarios = sorted(
        path.name for path in (root / "conformance/client-auth/scenarios").iterdir() if path.is_dir()
    )
    trust_tlog_baselines = sorted(
        path.stem for path in (root / "conformance/trust-tlog/baselines").glob("*.json")
    )
    return [
        {
            "id": "server-default",
            "kind": "server",
            "path": rel_to_repo(root / "conformance/run_server_conformance.sh"),
            "command": "conformance/run_server_conformance.sh",
            "supports": ["streamable-http", "streamable-http+sse"],
            "scenarios": server_default_scenarios,
        },
        {
            "id": "server-full",
            "kind": "server",
            "path": rel_to_repo(root / "conformance/run_server_conformance.sh"),
            "command": "conformance/run_server_conformance.sh --full-suite",
            "supports": ["streamable-http", "streamable-http+sse"],
            "scenarios": ["full-suite"],
        },
        {
            "id": "client-auth",
            "kind": "auth",
            "path": rel_to_repo(root / "scripts/conformance/run_client_auth_scenario.sh"),
            "command": "scripts/conformance/run_client_auth_scenario.sh <scenario>",
            "scenario_count": len(client_auth_scenarios),
            "scenarios": client_auth_scenarios,
        },
        {
            "id": "trust-tlog",
            "kind": "trust",
            "path": rel_to_repo(root / "conformance/trust-tlog/run.sh"),
            "command": "conformance/trust-tlog/run.sh",
            "baselines": trust_tlog_baselines,
        },
    ]


def _publish_capability_items(root: Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    roots = []
    roots.extend(path for path in (root / "templates").iterdir() if path.is_dir() and (path / "x07.mcp.json").is_file())
    roots.extend(path for path in (root / "servers").iterdir() if path.is_dir() and path.name != "_shared" and (path / "x07.mcp.json").is_file())
    for entry_dir in sorted(roots, key=lambda path: path.name):
        manifest = _load_json(entry_dir / "x07.mcp.json")
        publish = manifest.get("publish")
        publish_obj = publish if isinstance(publish, dict) else {}
        trust = publish_obj.get("trust_framework")
        trust_obj = trust if isinstance(trust, dict) else {}
        trust_pack = trust_obj.get("trust_pack")
        trust_pack_obj = trust_pack if isinstance(trust_pack, dict) else {}
        items.append(
            {
                "id": entry_dir.name,
                "kind": "template" if "templates" in entry_dir.parts else "reference-server",
                "identifier": str(manifest.get("identifier", "")),
                "version": str(manifest.get("version", "")),
                "path": rel_to_repo(entry_dir),
                "publish": {
                    "require_signed_prm": bool(publish_obj.get("require_signed_prm", False)),
                    "prm_path": str(publish_obj.get("prm", {}).get("path", "")) if isinstance(publish_obj.get("prm"), dict) else "",
                    "trust_framework_path": str(trust_obj.get("path", "")),
                    "trust_lock_path": str(trust_obj.get("trust_lock_path", "")),
                    "emit_meta_summary": bool(trust_obj.get("emit_meta_summary", False)),
                    "include_in_mcpb": bool(trust_obj.get("include_in_mcpb", False)),
                    "registry_manifest_path": "publish/server.mcp-registry.json" if (entry_dir / "publish/server.mcp-registry.json").is_file() else "",
                    "meta_summary_path": "publish/meta_summary.json" if (entry_dir / "publish/meta_summary.json").is_file() else "",
                    "trust_pack": {
                        "registry": str(trust_pack_obj.get("registry", "")),
                        "pack_id": str(trust_pack_obj.get("pack_id", "")),
                        "pack_version": str(trust_pack_obj.get("pack_version", "")),
                    },
                },
            }
        )
    return items


def _default_out(subcmd: str) -> Path:
    slug = re.sub(r"[^a-z0-9]+", "_", subcmd.lower()).strip("_")
    return repo_root() / ".x07/artifacts/mcp/catalog" / f"{slug}.json"


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit Forge-oriented MCP catalogs")
    parser.add_argument("subcmd", choices=["templates", "reference-servers", "conformance-suites", "publish-capabilities"])
    parser.add_argument("--out", default="")
    parser.add_argument("--machine", choices=["json"], default=None)
    args = parser.parse_args()

    root = repo_root()
    out_path = Path(args.out) if args.out else _default_out(args.subcmd)
    try:
        if args.subcmd == "templates":
            doc: dict[str, Any] = {
                "schema_version": "x07.mcp.template_catalog@0.1.0",
                "items": _template_items(root),
            }
        elif args.subcmd == "reference-servers":
            doc = {
                "schema_version": "x07.mcp.reference_server_catalog@0.1.0",
                "items": _reference_server_items(root),
            }
        elif args.subcmd == "conformance-suites":
            doc = {
                "schema_version": "x07.mcp.conformance_suite_catalog@0.1.0",
                "items": _conformance_suite_items(root),
            }
        else:
            doc = {
                "schema_version": "x07.mcp.publish_capability_summary@0.1.0",
                "items": _publish_capability_items(root),
            }
        doc["count"] = len(doc["items"])
        artifact_path = write_json(out_path, {**doc, "artifact_path": str(out_path.resolve())})
        doc["artifact_path"] = str(artifact_path.resolve())
    except Exception as exc:
        doc = {"ok": False, "error": str(exc)}
        sys.stdout.write(canonical_json_text(doc) if args.machine == "json" else json.dumps(doc, indent=2, sort_keys=True) + "\n")
        return 1

    sys.stdout.write(canonical_json_text(doc) if args.machine == "json" else json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
