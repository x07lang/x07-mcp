#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path

BLOCKED_TOP_LEVEL_KEYS = ("oneOf", "allOf", "anyOf")


def check_manifest(path: Path) -> list[str]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    tools = doc.get("tools", [])
    if not isinstance(tools, list):
        return [f"{path}: tools must be an array"]

    errors: list[str] = []
    for index, tool in enumerate(tools):
        if not isinstance(tool, dict):
            errors.append(f"{path}: tools[{index}] must be an object")
            continue
        name = tool.get("name", f"tools[{index}]")
        schema = tool.get("inputSchema")
        if not isinstance(schema, dict):
            errors.append(f"{path}: {name} missing object inputSchema")
            continue
        blocked = [key for key in BLOCKED_TOP_LEVEL_KEYS if key in schema]
        if blocked:
            keys = ", ".join(blocked)
            errors.append(
                f"{path}: {name} uses top-level {keys} in inputSchema; Claude rejects that shape"
            )
    return errors


def main(argv: list[str]) -> int:
    if argv:
        paths = [Path(arg) for arg in argv]
    else:
        root = Path(__file__).resolve().parents[1]
        paths = [
            root / "config" / "mcp.tools.json",
            root / "tests" / "config" / "mcp.tools.json",
        ]

    errors: list[str] = []
    for path in paths:
        errors.extend(check_manifest(path))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("ok: no top-level oneOf/allOf/anyOf in MCP tool input schemas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
