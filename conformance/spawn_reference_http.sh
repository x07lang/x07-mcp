#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_ID="${1:?missing server id}"
MODE="${2:?missing mode (noauth|oauth)}"

SERVER_ROOT="${ROOT}/servers/${SERVER_ID}"
if [[ ! -d "${SERVER_ROOT}" ]]; then
  echo "ERROR: server not found: ${SERVER_ROOT}" >&2
  exit 2
fi

CFG="config/mcp.server.http.json"
if [[ "${MODE}" == "oauth" ]]; then
  CFG="config/mcp.server.http.oauth.json"
elif [[ "${MODE}" == "noauth" ]]; then
  CFG="config/mcp.server.http.json"
else
  echo "ERROR: unknown mode: ${MODE}" >&2
  exit 2
fi

OUT_DIR="${SERVER_ROOT}/out"
mkdir -p "${OUT_DIR}"

"${ROOT}/servers/_shared/ci/install_server_deps.sh" "${SERVER_ROOT}"

echo "==> bundle router + worker (${SERVER_ID})"
x07 bundle --project "${SERVER_ROOT}/x07.json" --profile os --out "${OUT_DIR}/${SERVER_ID}" >/dev/null
(
  cd "${SERVER_ROOT}"
  WORKER_ENTRY="${OUT_DIR}/_worker_entry_main.x07.json"
  WORKER_PROJECT=".worker_project.x07.json"
  trap 'rm -f "${WORKER_PROJECT}"' EXIT
  cat > "${WORKER_ENTRY}" <<'JSON'
{"decls":[],"imports":["app","std.bytes","std.os.stdio","std.os.stdio.spec"],"kind":"entry","module_id":"main","schema_version":"x07.x07ast@0.5.0","solve":["begin",["let","caps",["std.os.stdio.spec.caps_default_v1"]],["let","caps_r",["std.bytes.copy","caps"]],["let","line_res",["std.os.stdio.read_line_v1","caps_r"]],["if",["!=",["result_bytes.err_code","line_res"],0],["bytes.alloc",0],["begin",["let","line",["result_bytes.unwrap_or","line_res",["bytes.alloc",0]]],["let","resp",["app.worker_main_v1",["bytes.view","line"]]],["let","nl",["bytes.alloc",1]],["set","nl",["bytes.set_u8","nl",0,10]],["let","out",["std.bytes.concat",["bytes.view","resp"],["bytes.view","nl"]]],["let","_w",["std.os.stdio.write_stdout_v1","out",["std.bytes.copy","caps"]]],["std.os.stdio.flush_stdout_v1"],["bytes.alloc",0]]]]}
JSON
  python3 - "${WORKER_PROJECT}" <<'PY'
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
project = json.loads(Path("x07.json").read_text(encoding="utf-8"))
roots = project.get("module_roots", [])
if "out" not in roots:
    roots = ["out", *roots]
project["module_roots"] = roots
project["entry"] = "out/_worker_entry_main.x07.json"
out_path.write_text(
    json.dumps(project, sort_keys=True, separators=(",", ":")),
    encoding="utf-8",
)
PY
  x07 bundle \
    --project "${WORKER_PROJECT}" \
    --profile sandbox \
    --sandbox-backend os \
    --i-accept-weaker-isolation \
    --out "${OUT_DIR}/mcp-worker" >/dev/null
)

echo "==> run router (${SERVER_ID}, ${MODE})"
export X07_MCP_CFG_PATH="${CFG}"
cd "${SERVER_ROOT}"
exec "${OUT_DIR}/${SERVER_ID}"
