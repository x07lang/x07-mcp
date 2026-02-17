#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_ID="${1:?missing server id}"
VERSION="${2:?missing version}"
SERVER_ROOT="${ROOT}/servers/${SERVER_ID}"
OUT_DIR="${SERVER_ROOT}/dist"
OUT_FILE="${OUT_DIR}/${SERVER_ID}.mcpb"

mkdir -p "${OUT_DIR}"

ROUTER_BIN="${SERVER_ROOT}/out/${SERVER_ID}"
WORKER_BIN="${SERVER_ROOT}/out/mcp-worker"

if [[ ! -x "${ROUTER_BIN}" ]]; then
  x07 bundle --project "${SERVER_ROOT}/x07.json" --profile os --out "${ROUTER_BIN}" >/dev/null
fi
if [[ ! -x "${WORKER_BIN}" ]]; then
  (
    cd "${SERVER_ROOT}"
    WORKER_ENTRY="${SERVER_ROOT}/out/_worker_entry_main.x07.json"
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
      --out "${WORKER_BIN}" >/dev/null
  )
fi

STAGE="$(mktemp -d)"
TMP_OUT_FILE=""
cleanup() {
  rm -rf "${STAGE}"
  if [[ -n "${TMP_OUT_FILE}" ]]; then
    rm -f "${TMP_OUT_FILE}"
  fi
}
trap cleanup EXIT

mkdir -p "${STAGE}/server" "${STAGE}/config" "${STAGE}/policy" "${STAGE}/arch/budgets"
cp "${SERVER_ROOT}/publish/manifest.json" "${STAGE}/manifest.json"
cp "${ROUTER_BIN}" "${STAGE}/server/${SERVER_ID}"
cp "${WORKER_BIN}" "${STAGE}/server/mcp-worker"
cp -R "${SERVER_ROOT}/config/." "${STAGE}/config/"
cp -R "${SERVER_ROOT}/policy/." "${STAGE}/policy/"
cp -R "${SERVER_ROOT}/arch/budgets/." "${STAGE}/arch/budgets/"

find "${STAGE}" -exec touch -t 200001010000 {} +

TMP_OUT_FILE="${OUT_FILE}.tmp"

npx -y @anthropic-ai/mcpb@2.1.2 pack "${STAGE}" "${TMP_OUT_FILE}"
npx -y @anthropic-ai/mcpb@2.1.2 clean "${TMP_OUT_FILE}" >/dev/null

python3 - "${TMP_OUT_FILE}" "${OUT_FILE}" <<'PY'
import sys
import zipfile

src_path = sys.argv[1]
dst_path = sys.argv[2]

fixed_ts = (2000, 1, 1, 0, 0, 0)

with zipfile.ZipFile(src_path, "r") as src, zipfile.ZipFile(
    dst_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
) as dst:
    for name in sorted(src.namelist()):
        info = src.getinfo(name)
        zi = zipfile.ZipInfo(filename=name, date_time=fixed_ts)
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.flag_bits = info.flag_bits
        zi.external_attr = info.external_attr
        zi.create_system = 3
        data = b"" if name.endswith("/") else src.read(name)
        dst.writestr(zi, data)
PY

rm -f "${TMP_OUT_FILE}"
TMP_OUT_FILE=""

shasum -a 256 "${OUT_FILE}" | awk '{print $1}' > "${OUT_FILE}.sha256.txt"
echo "built ${OUT_FILE}"
