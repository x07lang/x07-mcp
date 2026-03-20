#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVER_ID="${1:?missing server id}"
VERSION="${2:?missing version}"
SERVER_ROOT="${ROOT}/servers/${SERVER_ID}"
OUT_DIR="${SERVER_ROOT}/dist"
OUT_FILE="${OUT_DIR}/${SERVER_ID}.mcpb"
x07_root_resolver="${ROOT}/scripts/ci/resolve_workspace_x07_root.sh"

mkdir -p "${OUT_DIR}"

has_workspace_x07_candidate() {
  [[ -n "${X07_ROOT:-}" ]] || [[ -d "${ROOT}/x07" ]] || [[ -d "${ROOT}/../x07" ]]
}

resolve_x07_bin() {
  if [[ -n "${X07_MCP_X07_EXE:-}" ]]; then
    if [[ ! -x "${X07_MCP_X07_EXE}" ]]; then
      echo "ERROR: X07_MCP_X07_EXE is not executable: ${X07_MCP_X07_EXE}" >&2
      exit 2
    fi
    printf '%s\n' "${X07_MCP_X07_EXE}"
    return 0
  fi

  if has_workspace_x07_candidate; then
    local workspace_root=""
    workspace_root="$("${x07_root_resolver}")"
    local workspace_x07="${workspace_root}/target/debug/x07"
    if [[ -x "${workspace_x07}" ]]; then
      printf '%s\n' "${workspace_x07}"
      return 0
    fi
  fi

  command -v x07
}

X07_BIN="$(resolve_x07_bin)"

bundle_quiet_or_dump() {
  local log
  log="$(mktemp)"
  if ! "${X07_BIN}" bundle "$@" >"${log}" 2>&1; then
    cat "${log}" >&2
    rm -f "${log}"
    return 1
  fi
  rm -f "${log}"
  return 0
}

bundle_to_out_or_dump() {
  local out_path="${1:?missing output path}"
  shift

  local tmp_path
  tmp_path="${out_path}.tmp.$$"
  rm -f "${tmp_path}"
  if ! bundle_quiet_or_dump "$@" --out "${tmp_path}"; then
    rm -f "${tmp_path}"
    return 1
  fi
  mv "${tmp_path}" "${out_path}"
  return 0
}

validate_release_metadata() {
  python3 - "${SERVER_ROOT}" "${SERVER_ID}" "${VERSION}" <<'PY'
import json
import sys
from pathlib import Path

server_root = Path(sys.argv[1])
server_id = sys.argv[2]
version = sys.argv[3]

manifest_path = server_root / "publish" / "manifest.json"
x07_mcp_path = server_root / "x07.mcp.json"

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if str(manifest.get("version", "")) != version:
    raise SystemExit(
        f"publish/manifest.json version mismatch: got={manifest.get('version')!r} want={version!r}"
    )

x07_mcp = json.loads(x07_mcp_path.read_text(encoding="utf-8"))
if str(x07_mcp.get("version", "")) != version:
    raise SystemExit(
        f"x07.mcp.json version mismatch: got={x07_mcp.get('version')!r} want={version!r}"
    )

packages = x07_mcp.get("packages", [])
if not isinstance(packages, list) or not packages:
    raise SystemExit("x07.mcp.json must declare at least one package")

pkg = packages[0]
if str(pkg.get("version", "")) != version:
    raise SystemExit(
        f"x07.mcp.json package version mismatch: got={pkg.get('version')!r} want={version!r}"
    )

publisher_meta = (
    x07_mcp.get("_meta", {})
    .get("io.modelcontextprotocol.registry/publisher-provided", {})
)
if bool(publisher_meta.get("x07_official", False)):
    expected_url = (
        f"https://github.com/x07lang/x07-mcp/releases/download/{server_id}-v{version}/{server_id}.mcpb"
    )
    if str(pkg.get("url", "")) != expected_url:
        raise SystemExit(
            f"x07.mcp.json package url mismatch: got={pkg.get('url')!r} want={expected_url!r}"
        )

for rel_dir in ("config", "tests/config"):
    cfg_root = server_root / rel_dir
    if not cfg_root.is_dir():
        continue
    for cfg_path in sorted(cfg_root.glob("mcp.server*.json")):
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        server_meta = cfg.get("server")
        if not isinstance(server_meta, dict):
            raise SystemExit(f"{cfg_path.relative_to(server_root)} missing server object")
        cfg_version = str(server_meta.get("version", ""))
        if cfg_version != version:
            raise SystemExit(
                f"{cfg_path.relative_to(server_root)} version mismatch: "
                f"got={cfg_version!r} want={version!r}"
            )
PY
}

generate_server_json() {
  local is_official
  is_official="$(
    python3 - "${SERVER_ROOT}/x07.mcp.json" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
publisher_meta = (
    doc.get("_meta", {})
    .get("io.modelcontextprotocol.registry/publisher-provided", {})
)
print("1" if bool(publisher_meta.get("x07_official", False)) else "0")
PY
  )"
  if [[ "${is_official}" != "1" ]]; then
    return 0
  fi

  (
    cd "${ROOT}"
    python3 registry/scripts/registry_gen.py \
      --in "${SERVER_ROOT}/x07.mcp.json" \
      --out "${OUT_DIR}/server.json" \
      --mcpb "${OUT_FILE}" >/dev/null
    python3 registry/scripts/registry_gen.py \
      --in "${SERVER_ROOT}/x07.mcp.json" \
      --out "${SERVER_ROOT}/publish/server.mcp-registry.json" \
      --mcpb "${OUT_FILE}" >/dev/null
  )
}

resolve_worker_entry_schema_version() {
  python3 - "${SERVER_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

server_root = Path(sys.argv[1])
project = json.loads((server_root / "x07.json").read_text(encoding="utf-8"))
entry_rel = project.get("entry")
if not isinstance(entry_rel, str) or not entry_rel:
    raise SystemExit("x07.json missing entry")
entry_path = server_root / entry_rel
doc = json.loads(entry_path.read_text(encoding="utf-8"))
schema_version = doc.get("schema_version")
if not isinstance(schema_version, str) or not schema_version.startswith("x07.x07ast@"):
    raise SystemExit(
        f"failed to resolve x07AST schema_version from {entry_path.relative_to(server_root)}"
    )
print(schema_version)
PY
}

ROUTER_BIN="${SERVER_ROOT}/out/${SERVER_ID}"
WORKER_BIN="${SERVER_ROOT}/out/mcp-worker"
WORKER_ENTRY_SCHEMA_VERSION="$(resolve_worker_entry_schema_version)"

validate_release_metadata

bundle_to_out_or_dump "${ROUTER_BIN}" --project "${SERVER_ROOT}/x07.json" --profile os

(
  cd "${SERVER_ROOT}"
  WORKER_ENTRY="${SERVER_ROOT}/out/_worker_entry_main.x07.json"
  WORKER_PROJECT=".worker_project.x07.json"
  trap 'rm -f "${WORKER_PROJECT}"' EXIT
  python3 - "${WORKER_ENTRY}" "${WORKER_ENTRY_SCHEMA_VERSION}" <<'PY'
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
schema_version = sys.argv[2]
doc = {
    "decls": [],
    "imports": ["app", "std.bytes", "std.os.stdio", "std.os.stdio.spec"],
    "kind": "entry",
    "module_id": "main",
    "schema_version": schema_version,
    "solve": [
        "begin",
        ["let", "caps", ["std.os.stdio.spec.caps_default_v1"]],
        ["let", "caps_r", ["std.bytes.copy", "caps"]],
        ["let", "line_res", ["std.os.stdio.read_line_v1", "caps_r"]],
        [
            "if",
            ["!=", ["result_bytes.err_code", "line_res"], 0],
            ["bytes.alloc", 0],
            [
                "begin",
                ["let", "line", ["result_bytes.unwrap_or", "line_res", ["bytes.alloc", 0]]],
                ["let", "resp", ["app.worker_main_v1", ["bytes.view", "line"]]],
                ["let", "nl", ["bytes.alloc", 1]],
                ["set", "nl", ["bytes.set_u8", "nl", 0, 10]],
                ["let", "out", ["std.bytes.concat", ["bytes.view", "resp"], ["bytes.view", "nl"]]],
                ["let", "_w", ["std.os.stdio.write_stdout_v1", "out", ["std.bytes.copy", "caps"]]],
                ["std.os.stdio.flush_stdout_v1"],
                ["bytes.alloc", 0],
            ],
        ],
    ],
}
out_path.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
PY
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
  bundle_to_out_or_dump \
    "${WORKER_BIN}" \
    --project "${WORKER_PROJECT}" \
    --profile sandbox \
    --sandbox-backend os \
    --i-accept-weaker-isolation
)

if [[ "${X07_MCP_BUILD_BINS_ONLY:-0}" == "1" ]]; then
  echo "built ${ROUTER_BIN}"
  echo "built ${WORKER_BIN}"
  exit 0
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

mkdir -p "${STAGE}/server" "${STAGE}/out" "${STAGE}/config" "${STAGE}/policy" "${STAGE}/arch/budgets"
cp "${SERVER_ROOT}/publish/manifest.json" "${STAGE}/manifest.json"
cp "${ROUTER_BIN}" "${STAGE}/server/${SERVER_ID}"
cp "${WORKER_BIN}" "${STAGE}/out/mcp-worker"
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

generate_server_json

shasum -a 256 "${OUT_FILE}" | awk '{print $1}' > "${OUT_FILE}.sha256.txt"
echo "built ${OUT_FILE}"
