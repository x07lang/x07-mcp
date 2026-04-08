#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


_SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")
_LATEST_PROJECT_SCHEMA = "x07.project@0.4.0"
_X07_TOOLCHAIN_WORKFLOW_FILES = (
    Path(".github/workflows/ci.yml"),
    Path(".github/workflows/perf-smoke.yml"),
    Path(".github/workflows/trust-registry-monitor.yml"),
)


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


def _valid_workspace_x07_root(candidate: Path) -> bool:
    return candidate.is_dir() and (candidate / "crates" / "x07").is_dir() and (candidate / "stdlib.lock").is_file()


def _workspace_x07_root(repo_root: Path) -> Path | None:
    env_root = os.environ.get("X07_ROOT", "")
    if env_root:
        env_path = Path(env_root)
        candidates = [env_path] if env_path.is_absolute() else [Path.cwd() / env_path, repo_root / env_path]
        for candidate in candidates:
            candidate = candidate.resolve()
            if _valid_workspace_x07_root(candidate):
                return candidate
    for candidate in (repo_root / "x07", repo_root.parent / "x07"):
        candidate = candidate.resolve()
        if _valid_workspace_x07_root(candidate):
            return candidate
    return None


def _workspace_x07_packages_ext_root(repo_root: Path) -> Path | None:
    workspace_x07 = _workspace_x07_root(repo_root)
    if workspace_x07 is None:
        return None
    candidate = workspace_x07 / "packages" / "ext"
    if candidate.is_dir():
        return candidate
    return None


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


def _combined_latest_package_versions(packages_roots: list[Path]) -> dict[str, str]:
    best: dict[str, tuple[_Semver, str]] = {}
    for root in packages_roots:
        for name, ver_s in _latest_local_package_versions(root).items():
            ver = _parse_semver(ver_s)
            if ver is None:
                continue
            cur = best.get(name)
            if cur is None or (ver, ver_s) > cur:
                best[name] = (ver, ver_s)
    return {name: ver_s for name, (_ver, ver_s) in best.items()}


def _latest_registry_package_version(name: str) -> str | None:
    cmd = ["x07", "pkg", "versions", "--refresh", name]
    delay_secs = 1.0
    last_stderr = ""
    for attempt in range(1, 4):
        proc = subprocess.run(cmd, check=False, capture_output=True, text=True)
        if proc.returncode == 0:
            last_stderr = proc.stderr.strip()
            break
        last_stderr = proc.stderr.strip()
        if attempt == 3:
            return None
        time.sleep(delay_secs)
        delay_secs *= 2

    try:
        doc = json.loads(proc.stdout)
    except Exception:
        return None

    if not isinstance(doc, dict):
        return None
    if doc.get("ok") is not True:
        return None

    result = doc.get("result")
    if not isinstance(result, dict):
        return None
    versions = result.get("versions")
    if not isinstance(versions, list):
        return None

    best: tuple[_Semver, str] | None = None
    for entry in versions:
        if not isinstance(entry, dict):
            continue
        if entry.get("yanked") is True:
            continue
        ver_s = entry.get("version")
        if not isinstance(ver_s, str):
            continue
        ver = _parse_semver(ver_s)
        if ver is None:
            continue
        cand = (ver, ver_s)
        if best is None or cand > best:
            best = cand

    if best is None:
        return None
    if last_stderr:
        # Preserve a tiny amount of diagnostics context for debugging registry drift.
        # We intentionally do not print stderr here to keep CI output stable.
        pass
    return best[1]


def _pick_latest_version(*versions: str | None) -> str | None:
    best: tuple[_Semver, str] | None = None
    for ver_s in versions:
        if not ver_s:
            continue
        ver = _parse_semver(ver_s)
        if ver is None:
            continue
        cand = (ver, ver_s)
        if best is None or cand > best:
            best = cand
    if best is None:
        return None
    return best[1]


def _load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _iter_x07_projects(repo_root: Path) -> list[Path]:
    paths: list[Path] = []
    paths.append(repo_root / "x07.json")
    paths.append(repo_root / "conformance" / "client-x07" / "x07.json")
    paths.extend(sorted((repo_root / "templates").rglob("x07.json")))
    paths.extend(sorted((repo_root / "servers").rglob("x07.json")))
    examples_root = repo_root / "examples"
    if examples_root.is_dir():
        paths.extend(sorted(examples_root.rglob("x07.json")))
    docs_examples_root = repo_root / "docs" / "examples"
    if docs_examples_root.is_dir():
        paths.extend(sorted(docs_examples_root.rglob("x07.json")))
    return sorted({p for p in paths if p.is_file()})


def _iter_mcp_schema_json_files(repo_root: Path) -> list[Path]:
    roots = [
        repo_root / "templates",
        repo_root / "conformance",
        repo_root / "docs" / "examples",
        repo_root / "examples",
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
        repo_root / "docs" / "examples",
        repo_root / "examples",
        repo_root / "templates",
        repo_root / "conformance" / "client-x07" / "src",
        repo_root / "conformance" / "client-x07" / "tests",
        repo_root / "servers",
    ]

    out: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        for p in root.rglob("*.x07.json"):
            if not p.is_file():
                continue
            if any(
                part in {".git", ".x07", "target", "dist", ".agent_cache", "out", "tmp"}
                for part in p.parts
            ):
                continue
            out.append(p)
    return sorted(set(out))


def _extract_toml_string(path: Path, key: str) -> str | None:
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]+)"\s*$', _load_text(path), re.MULTILINE)
    if m is None:
        return None
    return m.group(1)


def _extract_yaml_env_string(path: Path, key: str) -> str | None:
    m = re.search(rf'^\s*{re.escape(key)}:\s*"([^"]+)"\s*$', _load_text(path), re.MULTILINE)
    if m is None:
        return None
    return m.group(1)


def _workspace_x07_release_tag(repo_root: Path) -> str | None:
    workspace_x07 = _workspace_x07_root(repo_root)
    if workspace_x07 is None:
        return None
    cargo_toml = workspace_x07 / "crates" / "x07" / "Cargo.toml"
    if not cargo_toml.is_file():
        return None
    version = _extract_toml_string(cargo_toml, "version")
    if version is None:
        return None
    return f"v{version}"


def _linux_x64_tarball_for_tag(tag: str) -> str | None:
    if not tag.startswith("v"):
        return None
    version = tag.removeprefix("v")
    if _parse_semver(version) is None:
        return None
    return f"x07-{version}-x86_64-unknown-linux-gnu.tar.gz"


def _git_stdout(repo_root: Path, *args: str) -> str | None:
    cp = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if cp.returncode != 0:
        return None
    return cp.stdout.strip()


def _workspace_x07_state_error(repo_root: Path, pinned_tag: str) -> str | None:
    workspace_x07 = _workspace_x07_root(repo_root)
    if workspace_x07 is None:
        return None

    if _git_stdout(workspace_x07, "rev-parse", "--git-dir") is None:
        return f"{workspace_x07}: not a git repo; cannot verify pinned tag {pinned_tag!r}"

    head_sha = _git_stdout(workspace_x07, "rev-parse", "HEAD^{commit}")
    tag_sha = _git_stdout(workspace_x07, "rev-parse", f"{pinned_tag}^{{commit}}")
    if not head_sha or not tag_sha:
        return f"{workspace_x07}: missing pinned tag {pinned_tag!r}; set X07_ROOT to a matching worktree"
    if head_sha != tag_sha:
        return (
            f"{workspace_x07}: workspace x07 checkout drift: "
            f"HEAD={head_sha[:12]!r} pinned {pinned_tag}={tag_sha[:12]!r}; "
            "checkout the pinned tag or set X07_ROOT to a matching worktree"
        )

    dirty = _git_stdout(workspace_x07, "status", "--short", "--untracked-files=no")
    if dirty is None:
        return f"{workspace_x07}: failed to read git status for pinned tag validation"
    if dirty:
        return f"{workspace_x07}: workspace x07 checkout has tracked local modifications; use a clean pinned-tag worktree"
    return None


def _schema_const_from_file(path: Path) -> str | None:
    try:
        doc = _load_json(path)
    except Exception:
        return None
    if not isinstance(doc, dict):
        return None
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


def _latest_x07ast_schema_version(repo_root: Path) -> str | None:
    workspace_x07 = _workspace_x07_root(repo_root)
    if workspace_x07 is not None:
        for candidate in (
            workspace_x07 / "spec" / "x07ast.schema.json",
            workspace_x07 / "docs" / "spec" / "schemas" / "x07ast.schema.json",
        ):
            if not candidate.is_file():
                continue
            value = _schema_const_from_file(candidate)
            if value is not None:
                return value
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
    "x07.mcp.prm_verify": "0.2.0",
    "x07.mcp.prompts_manifest": "0.1.0",
    "x07.mcp.resources_manifest": "0.1.0",
    "x07.mcp.rr.http_session": "0.1.0",
    "x07.mcp.server": "0.1.0",
    "x07.mcp.server_config": "0.3.0",
    "x07.mcp.tools_manifest": "0.2.0",
    "x07.mcp.trust.bundle": "0.1.0",
    "x07.mcp.trust.bundle_index": "0.1.0",
    "x07.mcp.trust.framework": "0.3.0",
    "x07.mcp.trust.lock": "0.2.0",
    "x07.mcp.trust.pack": "0.1.0",
    "x07.mcp.trust.pack_index": "0.1.0",
    "x07.mcp.trust.pack_manifest": "0.1.0",
    "x07.mcp.trust.registry": "0.2.0",
    "x07.mcp.trust.registry_index": "0.2.0",
    "x07.mcp.trust.registry_root": "0.2.0",
    "x07.mcp.trust.state": "0.1.0",
    "x07.mcp.trust.tlog.bundle": "0.1.0",
    "x07.mcp.trust.tlog.monitor_policy": "0.1.0",
    "x07.mcp.trust.tlog.monitor_state": "0.1.0",
    "x07.mcp.trust_anchors": "0.1.0",
}

_MCP_SCHEMA_ALLOWED_VERSIONS: dict[str, set[str]] = {
    "x07.mcp.server_config": {"0.2.0", "0.3.0"},
    "x07.mcp.trust.framework": {"0.2.0", "0.3.0"},
    "x07.mcp.trust.lock": {"0.1.0", "0.2.0"},
    "x07.mcp.trust.registry_root": {"0.1.0", "0.2.0"},
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
    packages_roots = [repo_root / "packages" / "ext"]
    workspace_x07_ext = _workspace_x07_packages_ext_root(repo_root)
    if workspace_x07_ext is not None:
        packages_roots.append(workspace_x07_ext)
    latest_pkg = _combined_latest_package_versions(packages_roots)
    registry_latest: dict[str, str | None] = {}

    errors: list[str] = []
    pinned_toolchain_path = repo_root / "x07-toolchain.toml"
    pinned_toolchain_tag = _extract_toml_string(pinned_toolchain_path, "channel")
    if pinned_toolchain_tag is None:
        errors.append(f"{pinned_toolchain_path}: missing channel pin")
    else:
        workspace_state_error = _workspace_x07_state_error(repo_root, pinned_toolchain_tag)
        if workspace_state_error is not None:
            errors.append(workspace_state_error)

        workspace_x07_tag = _workspace_x07_release_tag(repo_root)
        if workspace_x07_tag is not None and pinned_toolchain_tag != workspace_x07_tag:
            errors.append(
                f"{pinned_toolchain_path}: channel drift: got {pinned_toolchain_tag!r} want {workspace_x07_tag!r}"
            )

        want_tarball = _linux_x64_tarball_for_tag(pinned_toolchain_tag)
        if want_tarball is None:
            errors.append(
                f"{pinned_toolchain_path}: invalid pinned toolchain tag: {pinned_toolchain_tag!r}"
            )
        else:
            for rel_path in _X07_TOOLCHAIN_WORKFLOW_FILES:
                workflow_path = repo_root / rel_path
                workflow_tag = _extract_yaml_env_string(workflow_path, "X07_TOOLCHAIN_TAG")
                if workflow_tag != pinned_toolchain_tag:
                    errors.append(
                        f"{workflow_path}: X07_TOOLCHAIN_TAG drift: got {workflow_tag!r} want {pinned_toolchain_tag!r}"
                    )
                workflow_tarball = _extract_yaml_env_string(
                    workflow_path, "X07_TOOLCHAIN_TARBALL_LINUX_X64"
                )
                if workflow_tarball != want_tarball:
                    errors.append(
                        f"{workflow_path}: X07_TOOLCHAIN_TARBALL_LINUX_X64 drift: got {workflow_tarball!r} want {want_tarball!r}"
                    )

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
            dep_path = dep.get("path")
            dep_path_s = dep_path if isinstance(dep_path, str) else ""
            want_registry = registry_latest.get(name)
            if name not in registry_latest:
                want_registry = _latest_registry_package_version(name)
                registry_latest[name] = want_registry

            want_local = latest_pkg.get(name)
            want: str | None = None
            if dep_path_s.startswith(".x07/deps/"):
                if want_registry is None:
                    errors.append(f"{proj}: {name}@{version}: failed to query registry latest version")
                    continue
                want = want_registry
            else:
                want = _pick_latest_version(want_registry, want_local)
            if want is None:
                errors.append(f"{proj}: {name}@{version}: failed to resolve latest version")
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

    latest_x07ast = _latest_x07ast_schema_version(repo_root)
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
