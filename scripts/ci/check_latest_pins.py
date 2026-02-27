#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


_SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")
_LATEST_PROJECT_SCHEMA = "x07.project@0.3.0"


@dataclass(frozen=True, order=True)
class _Semver:
    major: int
    minor: int
    patch: int


def _parse_semver(text: str) -> _Semver | None:
    m = _SEMVER_RE.match(text)
    if not m:
        return None
    return _Semver(int(m.group(1)), int(m.group(2)), int(m.group(3)))


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _latest_local_package_versions(packages_root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for pkg_dir in sorted(packages_root.iterdir(), key=lambda p: p.name):
        if not pkg_dir.is_dir():
            continue
        if not pkg_dir.name.startswith("x07-"):
            continue

        dep_name = pkg_dir.name.removeprefix("x07-")
        best: tuple[_Semver, str] | None = None
        for ver_dir in pkg_dir.iterdir():
            if not ver_dir.is_dir():
                continue
            ver = _parse_semver(ver_dir.name)
            if ver is None:
                continue
            cand = (ver, ver_dir.name)
            if best is None or cand > best:
                best = cand
        if best is None:
            continue
        out[dep_name] = best[1]
    return out


def _load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _iter_x07_projects(repo_root: Path) -> list[Path]:
    paths: list[Path] = []

    paths.append(repo_root / "x07.json")
    paths.append(repo_root / "conformance" / "client-x07" / "x07.json")
    paths.extend(sorted((repo_root / "templates").glob("*/x07.json")))

    return [p for p in paths if p.is_file()]


def _iter_mcp_schema_json_files(repo_root: Path) -> list[Path]:
    roots = [
        repo_root / "templates",
        repo_root / "conformance",
    ]
    out: list[Path] = []
    for r in roots:
        if not r.is_dir():
            continue
        for p in r.rglob("*.json"):
            if not p.is_file():
                continue
            if ".x07" in p.parts:
                continue
            if "target" in p.parts:
                continue
            out.append(p)
    return sorted(out)


def _iter_x07_json_files(repo_root: Path) -> list[Path]:
    roots: list[Path] = [
        repo_root / "cli" / "src",
        repo_root / "templates",
        repo_root / "conformance" / "client-x07" / "src",
        repo_root / "conformance" / "client-x07" / "tests",
        repo_root / "servers",
    ]

    ext_root = repo_root / "packages" / "ext"
    app_root = repo_root / "packages" / "app"
    latest_ext = _latest_local_package_versions(ext_root)
    latest_app = _latest_local_package_versions(app_root)
    trust_ver = latest_ext.get("ext-mcp-trust")
    if trust_ver:
        roots.append(ext_root / "x07-ext-mcp-trust" / trust_ver / "modules")
    trust_os_ver = latest_ext.get("ext-mcp-trust-os")
    if trust_os_ver:
        roots.append(ext_root / "x07-ext-mcp-trust-os" / trust_os_ver / "modules")
    app_mcp_ver = latest_app.get("mcp")
    if app_mcp_ver:
        roots.append(app_root / "x07-mcp" / app_mcp_ver / "modules")

    out: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        for p in root.rglob("*.x07.json"):
            if not p.is_file():
                continue
            if any(part in {".git", ".x07", "target", "dist", ".agent_cache"} for part in p.parts):
                continue
            out.append(p)
    return sorted(set(out))


def _latest_x07ast_schema_version() -> str | None:
    try:
        proc = subprocess.run(
            ["x07", "ast", "schema", "--json=off"],
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return None
    try:
        doc = json.loads(proc.stdout)
        props = doc.get("properties")
        if not isinstance(props, dict):
            return None
        schema_version = props.get("schema_version")
        if not isinstance(schema_version, dict):
            return None
        value = schema_version.get("const")
        if not isinstance(value, str) or not value:
            return None
        return value
    except Exception:
        return None


_LATEST_MCP_SCHEMAS: dict[str, str] = {
    "x07.mcp.mock_as": "0.1.0",
    "x07.mcp.oauth": "0.2.0",
    "x07.mcp.prm_signing": "0.2.0",
    "x07.mcp.prompts_manifest": "0.1.0",
    "x07.mcp.resources_manifest": "0.1.0",
    "x07.mcp.rr.http_session": "0.1.0",
    "x07.mcp.server_config": "0.3.0",
    "x07.mcp.tools_manifest": "0.2.0",
    "x07.mcp.trust.bundle": "0.1.0",
    "x07.mcp.trust.framework": "0.3.0",
    "x07.mcp.trust.lock": "0.2.0",
    "x07.mcp.trust.registry": "0.2.0",
    "x07.mcp.trust_anchors": "0.1.0",
}

_MCP_SCHEMA_ALLOWED_VERSIONS: dict[str, set[str]] = {
    "x07.mcp.trust.framework": {"0.2.0", "0.3.0"},
    "x07.mcp.trust.lock": {"0.1.0", "0.2.0"},
}


def _parse_schema_id(text: str) -> tuple[str, str] | None:
    if "@" not in text:
        return None
    name, ver = text.split("@", 1)
    if not name.startswith("x07.mcp."):
        return None
    if _parse_semver(ver) is None:
        return None
    return name, ver


def main() -> int:
    repo_root = _repo_root()
    packages_root = repo_root / "packages" / "ext"
    latest_pkg = _latest_local_package_versions(packages_root)

    errors: list[str] = []

    for proj in _iter_x07_projects(repo_root):
        doc = _load_json(proj)
        if not isinstance(doc, dict):
            errors.append(f"{proj}: expected JSON object")
            continue

        schema_version = doc.get("schema_version")
        if schema_version != _LATEST_PROJECT_SCHEMA:
            errors.append(
                f"{proj}: schema_version drift: got {schema_version!r} want {_LATEST_PROJECT_SCHEMA!r}"
            )

        deps = doc.get("dependencies")
        if deps is None:
            continue
        if not isinstance(deps, list):
            errors.append(f"{proj}: dependencies: expected array")
            continue

        for i, dep in enumerate(deps):
            if not isinstance(dep, dict):
                errors.append(f"{proj}: dependencies[{i}]: expected object")
                continue
            name = dep.get("name")
            version = dep.get("version")
            if not isinstance(name, str) or not isinstance(version, str):
                continue
            want = latest_pkg.get(name)
            if want is None:
                continue
            if version != want:
                errors.append(f"{proj}: {name}@{version} is not latest (want {want})")

    for path in _iter_mcp_schema_json_files(repo_root):
        try:
            doc = _load_json(path)
        except Exception:
            continue
        if not isinstance(doc, dict):
            continue
        sv = doc.get("schema_version")
        if not isinstance(sv, str):
            continue
        parsed = _parse_schema_id(sv)
        if parsed is None:
            continue
        schema_name, schema_ver = parsed
        allowed = _MCP_SCHEMA_ALLOWED_VERSIONS.get(schema_name)
        if allowed is not None and schema_ver in allowed:
            continue
        want = _LATEST_MCP_SCHEMAS.get(schema_name)
        if want is None:
            continue
        if schema_ver != want:
            errors.append(f"{path}: schema_version drift: got {sv} want {schema_name}@{want}")

    latest_x07ast = _latest_x07ast_schema_version()
    if latest_x07ast is None:
        errors.append("failed to resolve latest x07ast schema_version via `x07 ast schema --json=off`")
    else:
        for path in _iter_x07_json_files(repo_root):
            try:
                doc = _load_json(path)
            except Exception:
                continue
            if not isinstance(doc, dict):
                continue
            sv = doc.get("schema_version")
            if not isinstance(sv, str):
                continue
            if sv.startswith("x07.x07ast@") and sv != latest_x07ast:
                errors.append(f"{path}: schema_version drift: got {sv!r} want {latest_x07ast!r}")
            if sv.startswith("x07.project@") and sv != _LATEST_PROJECT_SCHEMA:
                errors.append(f"{path}: schema_version drift: got {sv!r} want {_LATEST_PROJECT_SCHEMA!r}")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 2

    print("ok: latest pins and MCP schemas are consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
