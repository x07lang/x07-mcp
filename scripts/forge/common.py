#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


REPO_ROOT = repo_root()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def canonical_json_text(doc: Any) -> str:
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def write_json(path: Path, doc: Any) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical_json_text(doc), encoding="utf-8")
    return path


def parse_json_arg(text: str | None, *, default: Any, what: str) -> Any:
    if not text:
        return default
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid {what}: {exc}") from exc


def first_heading_and_summary(readme_path: Path) -> tuple[str, str]:
    if not readme_path.is_file():
        return ("", "")

    title = ""
    summary_lines: list[str] = []
    saw_heading = False
    for raw_line in readme_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not saw_heading:
            if line.startswith("# "):
                title = line[2:].strip()
                saw_heading = True
            continue
        if not line:
            if summary_lines:
                break
            continue
        if line.startswith("#"):
            break
        summary_lines.append(line)
    return (title, " ".join(summary_lines).strip())


def rel_to_repo(path: Path) -> str:
    return path.resolve().relative_to(repo_root()).as_posix()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _artifact_path(group: str, name: str, out: str | None) -> Path:
    if out:
        return Path(out).resolve()
    return REPO_ROOT / ".x07" / "artifacts" / "mcp" / group / f"{name}.json"


def emit(doc: dict[str, Any], *, out: str | None, group: str, name: str, machine: str | None) -> int:
    artifact_path = _artifact_path(group, name, out)
    final_doc = dict(doc)
    final_doc["artifact_path"] = str(artifact_path)
    write_json(artifact_path, final_doc)
    if machine == "json":
        sys.stdout.write(canonical_json_text(final_doc))
    else:
        sys.stdout.write(json.dumps(final_doc, indent=2, sort_keys=True) + "\n")
    return 0 if final_doc.get("ok", True) else 1


def emit_error(
    message: str,
    *,
    out: str | None,
    group: str,
    name: str,
    machine: str | None,
    extra: dict[str, Any] | None = None,
) -> int:
    doc = {"ok": False, "error": message}
    if extra:
        doc.update(extra)
    return emit(doc, out=out, group=group, name=name, machine=machine)
