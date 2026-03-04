#!/usr/bin/env bash
set -euo pipefail

IFS= read -r req || true

python3 - "$req" <<'PY'
import json
import os
import sys
import time

req_s = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    req = json.loads(req_s) if req_s else {}
except Exception as e:
    sys.stderr.write(f"invalid json request: {e}\n")
    raise SystemExit(2)

args = {}
for path in [
    ("params", "arguments"),
    ("params", "args"),
    ("params",),
    ("arguments",),
    ("args",),
]:
    cur = req
    ok = True
    for k in path:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            ok = False
            break
    if ok and isinstance(cur, dict):
        args = cur
        break

started_path = args.get("started_path") or args.get("startedPath") or ""
release_path = args.get("release_path") or args.get("releasePath") or ""

if started_path:
    os.makedirs(os.path.dirname(started_path) or ".", exist_ok=True)
    with open(started_path, "wb") as f:
        f.write(b"1")

if release_path:
    deadline = time.time() + 10.0
    while not os.path.exists(release_path):
        if time.time() > deadline:
            sys.stderr.write(f"timeout waiting for release file: {release_path}\n")
            raise SystemExit(3)
        time.sleep(0.01)

print('{"toolResult":{"content":[{"type":"text","text":"ok"}]}}')
PY
