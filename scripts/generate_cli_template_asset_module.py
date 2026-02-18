#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path


def _should_skip_rel(rel_posix: str) -> bool:
    parts = rel_posix.split("/")
    if not parts:
        return True

    top = parts[0]
    if top in {".git", ".x07", "target", "dist", "out", "artifacts"}:
        return True
    if top.startswith("tmp"):
        return True
    if rel_posix.endswith("/.DS_Store") or rel_posix == ".DS_Store":
        return True

    return False


def _iter_files(template_dir: Path) -> list[tuple[str, Path]]:
    files: list[tuple[str, Path]] = []
    for p in template_dir.rglob("*"):
        if p.is_dir():
            continue
        rel = p.relative_to(template_dir).as_posix()
        if _should_skip_rel(rel):
            continue
        files.append((rel, p))
    files.sort(key=lambda it: it[0])
    return files


def _b64_bytes(b: bytes) -> str:
    return base64.b64encode(b).decode("ascii")


def _make_asset_module(module_id: str, files: list[tuple[str, Path]]) -> dict:
    exports = [f"{module_id}.get_b64_v1", f"{module_id}.paths_text_v1"]

    get_b64_body: list = ["begin"]
    for i, (rel, src_path) in enumerate(files):
        var = f"_p_{i}"
        get_b64_body.append(["let", var, ["bytes.lit", rel]])
        b64 = _b64_bytes(src_path.read_bytes())
        get_b64_body.append(
            [
                "if",
                ["=", ["std.bytes.eq", "path", ["bytes.view", var]], 1],
                ["return", ["option_bytes.some", ["bytes.lit", b64]]],
                0,
            ]
        )
    get_b64_body.append(["option_bytes.none"])

    paths_text = "\n".join([rel for (rel, _) in files])

    return {
        "decls": [
            {"kind": "export", "names": exports},
            {
                "body": get_b64_body,
                "kind": "defn",
                "name": f"{module_id}.get_b64_v1",
                "params": [{"name": "path", "ty": "bytes_view"}],
                "result": "option_bytes",
            },
            {
                "body": ["bytes.lit", paths_text],
                "kind": "defn",
                "name": f"{module_id}.paths_text_v1",
                "params": [],
                "result": "bytes",
            },
        ],
        "imports": ["std.bytes"],
        "kind": "module",
        "module_id": module_id,
        "schema_version": "x07.x07ast@0.5.0",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--template-dir", type=Path, required=True)
    ap.add_argument("--module-id", type=str, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    template_dir: Path = args.template_dir
    if not template_dir.is_dir():
        raise SystemExit(f"--template-dir is not a directory: {template_dir}")

    files = _iter_files(template_dir)
    if not files:
        raise SystemExit(f"no files found under template dir: {template_dir}")

    doc = _make_asset_module(args.module_id, files)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

