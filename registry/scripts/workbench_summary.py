#!/usr/bin/env python3
from __future__ import annotations

import pathlib
from typing import Any

from registry_lib import (
    _discover_repo_root,
    _package_transport_from_input,
    canonical_json_text,
    extract_publish_meta_x07,
    infer_manifest_path_for_server_json,
    parse_publish_trust_config,
    read_json,
    sha256_file,
    validate_non_schema_constraints,
    validate_schema,
    verify_publish_trust_policy,
)


BUNDLE_SCHEMA = "x07.mcp.bundle.summary@0.1.0"
PUBLISH_SCHEMA = "x07.mcp.publish.readiness@0.1.0"


def _first_mcpb_package(server_doc: dict[str, Any]) -> dict[str, Any] | None:
    packages = server_doc.get("packages")
    if not isinstance(packages, list):
        return None
    for pkg in packages:
        if isinstance(pkg, dict) and str(pkg.get("registryType", "")) == "mcpb":
            return pkg
    return None


def _relative_path(path: pathlib.Path | None, repo_root: pathlib.Path | None) -> str:
    if path is None:
        return ""
    resolved = path.resolve()
    if repo_root is not None:
        root = repo_root.resolve()
        if resolved == root or root in resolved.parents:
            return str(resolved.relative_to(root))
    return str(resolved)


def _load_json_object(path: pathlib.Path) -> dict[str, Any]:
    doc = read_json(path)
    if not isinstance(doc, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return doc


def _artifact_paths(
    *,
    repo_root: pathlib.Path | None,
    server_json_path: pathlib.Path,
    mcpb_path: pathlib.Path,
    server_manifest_path: pathlib.Path | None,
    package_manifest_path: pathlib.Path | None,
    meta_summary_path: pathlib.Path | None,
    registry_manifest_path: pathlib.Path | None,
) -> dict[str, str]:
    artifacts = {
        "server_json_path": _relative_path(server_json_path, repo_root),
        "mcpb_path": _relative_path(mcpb_path, repo_root),
    }
    if server_manifest_path is not None:
        artifacts["server_manifest_path"] = _relative_path(server_manifest_path, repo_root)
    if package_manifest_path is not None:
        artifacts["package_manifest_path"] = _relative_path(package_manifest_path, repo_root)
    if meta_summary_path is not None:
        artifacts["meta_summary_path"] = _relative_path(meta_summary_path, repo_root)
    if registry_manifest_path is not None:
        artifacts["registry_manifest_path"] = _relative_path(registry_manifest_path, repo_root)
    return artifacts


def _append_finding(items: list[dict[str, str]], code: str, message: str) -> None:
    items.append({"code": code, "message": message})


def _error_code_from_text(message: str, default_code: str) -> str:
    prefix = message.split(":", 1)[0].strip()
    if prefix.startswith("MCP_"):
        return prefix
    return default_code


def _status_from_findings(blockers: list[dict[str, str]], warnings: list[dict[str, str]]) -> str:
    if blockers:
        return "blocked"
    if warnings:
        return "warn"
    return "ready"


def _sequence_count(doc: dict[str, Any], key: str) -> int:
    value = doc.get(key)
    if isinstance(value, list):
        return len(value)
    return 0


def _capability_summary(server_dir: pathlib.Path, repo_root: pathlib.Path | None) -> dict[str, Any]:
    config_path = server_dir / "config" / "mcp.server.json"
    if not config_path.is_file():
        return {
            "status": "missing",
            "config_path": _relative_path(config_path, repo_root),
            "tool_count": 0,
            "resource_count": 0,
            "prompt_count": 0,
        }

    cfg = _load_json_object(config_path)
    tools_doc = _load_json_object(server_dir / "config" / "mcp.tools.json")
    resources_doc = _load_json_object(server_dir / "config" / "mcp.resources.json")
    prompts_doc = _load_json_object(server_dir / "config" / "mcp.prompts.json")

    transports = cfg.get("transports")
    transports_obj = transports if isinstance(transports, dict) else {}
    http_cfg = transports_obj.get("http")
    http_obj = http_cfg if isinstance(http_cfg, dict) else {}

    capabilities = cfg.get("capabilities")
    capabilities_obj = capabilities if isinstance(capabilities, dict) else {}
    tools_caps = capabilities_obj.get("tools")
    tools_caps_obj = tools_caps if isinstance(tools_caps, dict) else {}
    tasks_caps = capabilities_obj.get("tasks")
    tasks_caps_obj = tasks_caps if isinstance(tasks_caps, dict) else {}
    requests_caps = tasks_caps_obj.get("requests")
    requests_obj = requests_caps if isinstance(requests_caps, dict) else {}
    task_tools = requests_obj.get("tools")
    task_tools_obj = task_tools if isinstance(task_tools, dict) else {}

    auth = cfg.get("auth")
    auth_obj = auth if isinstance(auth, dict) else {}
    server_meta = cfg.get("server")
    server_meta_obj = server_meta if isinstance(server_meta, dict) else {}

    return {
        "status": "available",
        "config_path": _relative_path(config_path, repo_root),
        "protocol_version": str(server_meta_obj.get("protocolVersion", "")),
        "auth_mode": str(auth_obj.get("mode", "none")),
        "http_enabled": bool(http_obj.get("enabled", False)),
        "tool_count": _sequence_count(tools_doc, "tools"),
        "resource_count": _sequence_count(resources_doc, "resources"),
        "prompt_count": _sequence_count(prompts_doc, "prompts"),
        "flags": {
            "tools_list_changed": bool(tools_caps_obj.get("listChanged", False)),
            "tasks_enabled": bool(cfg.get("tasks", {}).get("enabled", False))
            if isinstance(cfg.get("tasks"), dict)
            else False,
            "tasks_list": isinstance(tasks_caps_obj.get("list"), dict),
            "tasks_cancel": isinstance(tasks_caps_obj.get("cancel"), dict),
            "task_tool_call": isinstance(task_tools_obj.get("call"), dict),
        },
    }


def _official_server_id(server_doc: dict[str, Any], fallback: str) -> str:
    meta = server_doc.get("_meta")
    if isinstance(meta, dict):
        publisher = meta.get("io.modelcontextprotocol.registry/publisher-provided")
        if isinstance(publisher, dict):
            server_id = publisher.get("server_id")
            if isinstance(server_id, str) and server_id:
                return server_id
    return fallback


def _server_identity(
    *,
    server_doc: dict[str, Any] | None,
    server_dir: pathlib.Path | None,
    fallback_name: str,
    repo_root: pathlib.Path | None,
) -> dict[str, str]:
    if isinstance(server_doc, dict):
        identifier = str(server_doc.get("name") or server_doc.get("identifier") or fallback_name)
        display_name = str(server_doc.get("title") or server_doc.get("display_name") or server_doc.get("name") or fallback_name)
        version = str(server_doc.get("version", ""))
        server_id = _official_server_id(server_doc, server_dir.name if server_dir is not None else fallback_name)
    else:
        identifier = fallback_name
        display_name = fallback_name
        version = ""
        server_id = server_dir.name if server_dir is not None else fallback_name
    identity = {
        "id": server_id,
        "identifier": identifier,
        "display_name": display_name,
        "version": version,
    }
    if server_dir is not None:
        identity["server_dir"] = _relative_path(server_dir, repo_root)
    return identity


def _readiness_warnings_from_manifest(
    *,
    cfg: Any,
    warnings: list[dict[str, str]],
    meta_summary_path: pathlib.Path | None,
) -> None:
    if cfg is None:
        return
    if not cfg.require_signed_prm:
        _append_finding(
            warnings,
            "MCP_PUBLISH_PRM_UNSIGNED_ALLOWED",
            "publish.require_signed_prm is disabled; publish metadata can be produced without signed PRM.",
        )
    if not cfg.emit_meta_summary:
        _append_finding(
            warnings,
            "MCP_PUBLISH_META_SUMMARY_DISABLED",
            "publish.trust_framework.emit_meta_summary is disabled; server.json will not carry the x07 trust overlay.",
        )
    trust_pack_configured = bool(
        cfg.trust_pack_registry
        or cfg.trust_pack_id
        or cfg.trust_pack_version
        or cfg.trust_pack_min_snapshot_version is not None
        or cfg.trust_pack_snapshot_sha256
        or cfg.trust_pack_checkpoint_sha256
    )
    if not trust_pack_configured:
        _append_finding(
            warnings,
            "MCP_PUBLISH_TRUST_PACK_UNCONFIGURED",
            "trust pack metadata is not configured; anti-rollback readiness is limited to local trust pins.",
        )
    if cfg.emit_meta_summary and meta_summary_path is not None and not meta_summary_path.is_file():
        _append_finding(
            warnings,
            "MCP_PUBLISH_META_SUMMARY_FILE_MISSING",
            "publish/meta_summary.json is missing; trust summary was not materialized as a standalone artifact yet.",
        )


def _next_steps(
    *,
    blockers: list[dict[str, str]],
    warnings: list[dict[str, str]],
    server_json_path: pathlib.Path,
    mcpb_path: pathlib.Path,
    repo_root: pathlib.Path | None,
    for_bundle: bool,
) -> list[str]:
    steps: list[str] = []
    codes = {item["code"] for item in blockers}
    if "MCP_PUBLISH_MCPB_SHA_MISMATCH" in codes:
        steps.append(
            "Rebuild the .mcpb bundle and regenerate server.json so fileSha256 matches the artifact bytes."
        )
    if "MCP_PUBLISH_TRUST_META_MISMATCH" in codes:
        steps.append(
            "Regenerate server.json from x07.mcp.json so the embedded x07 trust summary matches the current trust inputs."
        )
    if "MCP_PUBLISH_TRUST_PINS_MISSING" in codes:
        steps.append(
            "Fix the publish trust framework, trust lock, or trust pack pins before re-running publish dry-run."
        )
    if "MCP_PUBLISH_PRM_UNSIGNED" in codes:
        steps.append(
            "Generate or refresh publish/prm.json with signed_metadata before re-running publish dry-run."
        )
    if "MCP_PUBLISH_SERVER_JSON_MISSING" in codes:
        steps.append("Generate server.json from x07.mcp.json before validating publish readiness.")
    if "MCP_PUBLISH_MCPB_MISSING" in codes:
        steps.append("Build the .mcpb artifact before validating publish readiness.")
    if not steps and warnings:
        steps.append("Resolve the readiness warnings before treating the server as release-ready.")
    if not steps and for_bundle:
        steps.append(
            "Run x07-mcp publish --dry-run --server-json "
            f"{_relative_path(server_json_path, repo_root)} --mcpb {_relative_path(mcpb_path, repo_root)} --machine json "
            "before pushing the bundle to a registry."
        )
    if not steps:
        steps.append("Publish dry-run passed; the bundle is ready for the normal release and registry publish flow.")
    return steps


def compute_publish_readiness(
    *,
    server_json_path: pathlib.Path,
    mcpb_path: pathlib.Path,
    schema_path: pathlib.Path,
    schema_url: str,
    manifest_path_override: pathlib.Path | None = None,
    prm_path_override: pathlib.Path | None = None,
    trust_framework_path_override: pathlib.Path | None = None,
) -> tuple[dict[str, Any], dict[str, Any] | None, pathlib.Path | None]:
    blockers: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    trust_summary: dict[str, Any] | None = None

    repo_root = _discover_repo_root(server_json_path)
    manifest_path = manifest_path_override or infer_manifest_path_for_server_json(server_json_path)
    server_dir = manifest_path.parent if manifest_path is not None else server_json_path.parent.parent
    package_manifest_path = server_dir / "publish" / "manifest.json"
    meta_summary_path = server_dir / "publish" / "meta_summary.json"
    registry_manifest_path = server_dir / "publish" / "server.mcp-registry.json"

    server_doc: dict[str, Any] | None = None
    manifest_doc: dict[str, Any] | None = None
    package_manifest_doc: dict[str, Any] | None = None
    pkg: dict[str, Any] | None = None
    mcpb_sha = ""

    if not server_json_path.is_file():
        _append_finding(
            blockers,
            "MCP_PUBLISH_SERVER_JSON_MISSING",
            f"missing server.json file: {server_json_path}",
        )
    else:
        try:
            server_doc = _load_json_object(server_json_path)
        except Exception as exc:
            _append_finding(
                blockers,
                "MCP_PUBLISH_SERVER_JSON_INVALID",
                str(exc),
            )

    if not mcpb_path.is_file():
        _append_finding(
            blockers,
            "MCP_PUBLISH_MCPB_MISSING",
            f"missing mcpb file: {mcpb_path}",
        )
    else:
        mcpb_sha = sha256_file(mcpb_path)

    if server_doc is not None:
        try:
            if str(server_doc.get("$schema", "")) != schema_url:
                raise ValueError(f"server.json $schema must be {schema_url}")
            validate_schema(server_doc, schema_path)
            validate_non_schema_constraints(server_doc)
        except Exception as exc:
            _append_finding(
                blockers,
                _error_code_from_text(str(exc), "MCP_PUBLISH_SERVER_JSON_SCHEMA_INVALID"),
                str(exc),
            )

        pkg = _first_mcpb_package(server_doc)
        if pkg is None:
            _append_finding(
                blockers,
                "MCP_PUBLISH_MCPB_PACKAGE_MISSING",
                "server.json must include at least one mcpb package.",
            )
        elif mcpb_sha:
            expected_sha = str(pkg.get("fileSha256", ""))
            if not expected_sha:
                _append_finding(
                    blockers,
                    "MCP_PUBLISH_MCPB_SHA_MISSING",
                    "mcpb package is missing fileSha256.",
                )
            elif expected_sha != mcpb_sha:
                _append_finding(
                    blockers,
                    "MCP_PUBLISH_MCPB_SHA_MISMATCH",
                    f"mcpb sha mismatch: expected {expected_sha}, got {mcpb_sha}",
                )

    cfg = None
    if manifest_path is None:
        _append_finding(
            warnings,
            "MCP_PUBLISH_MANIFEST_UNAVAILABLE",
            "x07.mcp.json was not found next to server.json; publish trust metadata cannot be fully resolved.",
        )
    else:
        try:
            manifest_doc = _load_json_object(manifest_path)
            cfg = parse_publish_trust_config(manifest_doc)
            _readiness_warnings_from_manifest(
                cfg=cfg,
                warnings=warnings,
                meta_summary_path=meta_summary_path,
            )
        except Exception as exc:
            _append_finding(
                blockers,
                _error_code_from_text(str(exc), "MCP_PUBLISH_MANIFEST_INVALID"),
                str(exc),
            )
    if package_manifest_path.is_file():
        try:
            package_manifest_doc = _load_json_object(package_manifest_path)
        except Exception as exc:
            _append_finding(
                warnings,
                "MCP_PUBLISH_PACKAGE_MANIFEST_INVALID",
                str(exc),
            )

    if server_doc is not None and manifest_path is not None and mcpb_path.is_file():
        try:
            trust_summary, manifest_path = verify_publish_trust_policy(
                server_doc=server_doc,
                server_json_path=server_json_path,
                manifest_path=manifest_path,
                prm_path_override=prm_path_override,
                trust_framework_path_override=trust_framework_path_override,
            )
        except Exception as exc:
            _append_finding(
                blockers,
                _error_code_from_text(str(exc), "MCP_PUBLISH_DRY_RUN_FAILED"),
                str(exc),
            )

    capability_summary = _capability_summary(server_dir, repo_root)
    identity = _server_identity(
        server_doc=server_doc,
        server_dir=server_dir,
        fallback_name=server_dir.name,
        repo_root=repo_root,
    )
    status = _status_from_findings(blockers, warnings)

    publish_doc = {
        "schema_version": PUBLISH_SCHEMA,
        "subcommand": "publish",
        "ok": not blockers,
        "status": status,
        "run_ref": f"publish-readiness:{mcpb_sha[:16] or 'missing'}",
        "server": identity,
        "bundle": {
            "path": _relative_path(mcpb_path, repo_root),
            "sha256": mcpb_sha,
            "registry_type": str(pkg.get("registryType", "")) if isinstance(pkg, dict) else "",
            "transport": _package_transport_from_input(pkg) if isinstance(pkg, dict) else {},
            "version": str(pkg.get("version", identity.get("version", ""))) if isinstance(pkg, dict) else identity.get("version", ""),
            "identifier": str(pkg.get("identifier", identity.get("identifier", ""))) if isinstance(pkg, dict) else identity.get("identifier", ""),
        },
        "capabilities": capability_summary,
        "trust": {
            "status": "blocked" if blockers else ("warn" if warnings else "healthy"),
            "meta_summary_present": meta_summary_path.is_file(),
            "registry_manifest_present": registry_manifest_path.is_file(),
            "x07_meta": trust_summary.get("x07") if isinstance(trust_summary, dict) else extract_publish_meta_x07(server_doc or {}),
        },
        "publish": {
            "status": status,
            "blocker_count": len(blockers),
            "warning_count": len(warnings),
            "server_schema": str(server_doc.get("$schema", "")) if isinstance(server_doc, dict) else "",
            "manifest_version": str(package_manifest_doc.get("manifest_version", "")) if isinstance(package_manifest_doc, dict) else "",
            "package_version": str(package_manifest_doc.get("version", "")) if isinstance(package_manifest_doc, dict) else "",
        },
        "blockers": blockers,
        "warnings": warnings,
        "next_steps": _next_steps(
            blockers=blockers,
            warnings=warnings,
            server_json_path=server_json_path,
            mcpb_path=mcpb_path,
            repo_root=repo_root,
            for_bundle=False,
        ),
        "artifacts": _artifact_paths(
            repo_root=repo_root,
            server_json_path=server_json_path,
            mcpb_path=mcpb_path,
            server_manifest_path=manifest_path,
            package_manifest_path=package_manifest_path if package_manifest_path.is_file() else package_manifest_path,
            meta_summary_path=meta_summary_path if meta_summary_path.is_file() else meta_summary_path,
            registry_manifest_path=registry_manifest_path if registry_manifest_path.is_file() else registry_manifest_path,
        ),
    }
    return publish_doc, trust_summary, manifest_path


def compute_bundle_summary(
    *,
    server_dir: pathlib.Path,
    mcpb_path: pathlib.Path,
    server_json_path: pathlib.Path | None = None,
) -> dict[str, Any]:
    server_dir = server_dir.resolve()
    repo_root = _discover_repo_root(server_dir)
    server_json = server_json_path or server_dir / "dist" / "server.json"
    publish_doc, _, manifest_path = compute_publish_readiness(
        server_json_path=server_json,
        mcpb_path=mcpb_path,
        schema_path=repo_root / "registry" / "schema" / "server.schema.2025-12-11.json",
        schema_url="https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
    )
    try:
        server_doc = _load_json_object(server_json) if server_json.is_file() else None
    except Exception:
        server_doc = None
    pkg = _first_mcpb_package(server_doc) if isinstance(server_doc, dict) else None

    bundle_status = publish_doc["status"]
    bundle_doc = {
        "schema_version": BUNDLE_SCHEMA,
        "subcommand": "bundle",
        "ok": True,
        "status": bundle_status,
        "run_ref": f"bundle:{publish_doc['bundle']['sha256'][:16] or 'missing'}",
        "server": publish_doc["server"],
        "bundle": {
            "path": publish_doc["bundle"]["path"],
            "sha256": publish_doc["bundle"]["sha256"],
            "identifier": publish_doc["bundle"]["identifier"],
            "version": publish_doc["bundle"]["version"],
            "registry_type": publish_doc["bundle"]["registry_type"],
            "transport": publish_doc["bundle"]["transport"],
            "package_url": str(pkg.get("url", "")) if isinstance(pkg, dict) else "",
        },
        "capabilities": publish_doc["capabilities"],
        "publish": publish_doc["publish"],
        "trust": publish_doc["trust"],
        "blockers": publish_doc["blockers"],
        "warnings": publish_doc["warnings"],
        "next_steps": _next_steps(
            blockers=publish_doc["blockers"],
            warnings=publish_doc["warnings"],
            server_json_path=server_json,
            mcpb_path=mcpb_path,
            repo_root=repo_root,
            for_bundle=True,
        ),
        "artifacts": _artifact_paths(
            repo_root=repo_root,
            server_json_path=server_json,
            mcpb_path=mcpb_path,
            server_manifest_path=manifest_path,
            package_manifest_path=server_dir / "publish" / "manifest.json",
            meta_summary_path=server_dir / "publish" / "meta_summary.json",
            registry_manifest_path=server_dir / "publish" / "server.mcp-registry.json",
        ),
    }
    return bundle_doc


__all__ = [
    "BUNDLE_SCHEMA",
    "PUBLISH_SCHEMA",
    "canonical_json_text",
    "compute_bundle_summary",
    "compute_publish_readiness",
]
