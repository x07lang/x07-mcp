#!/usr/bin/env bash
set -euo pipefail

# Installs a released x07lang-mcp .mcpb bundle for Claude Code / CLI MCP clients.
#
# Downloads the bundle and its .sha256.txt from the GitHub release for the tag
# (unless --mcpb points at a local bundle), verifies the sha256, extracts the
# bundle under ~/.local/share/x07lang-mcp/releases/<tag>/bundle, smoke-tests it
# (initialize handshake) BEFORE repointing the ~/.local/share/x07lang-mcp/current
# symlink atomically, and (re)writes the x07lang-mcp-stdio wrapper used for client
# registration. --rollback repoints current at the previously installed release.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${HOME}/.local/share/x07lang-mcp"
BIN_DIR="${STATE_DIR}/bin"
WRAPPER="${BIN_DIR}/x07lang-mcp-stdio"
CURRENT_LINK="${STATE_DIR}/current"
RELEASE_BASE_URL="https://github.com/x07lang/x07-mcp/releases/download"

usage() {
  cat <<'EOF'
Usage: install_local.sh [--tag x07lang-mcp-vX.Y.Z] [--mcpb path/to/x07lang-mcp.mcpb]
       install_local.sh --rollback
       install_local.sh --uninstall

Installs a released x07lang-mcp bundle under ~/.local/share/x07lang-mcp and
prints the `claude mcp add` registration command.

Options:
  --tag TAG    Release tag to install (default: x07lang-mcp-v<version> from x07.mcp.json)
  --mcpb PATH  Install a local bundle instead of downloading the release asset
  --rollback   Repoint `current` at the previously installed release
  --uninstall  Remove ~/.local/share/x07lang-mcp (releases, current symlink, wrapper)
  -h, --help   Show this help
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "missing command: shasum or sha256sum"
  fi
}

# Read a sha from a .sha256.txt file, tolerating either a bare digest or the
# `<digest>  <filename>` shasum format (take the first whitespace-delimited field).
read_sha_file() {
  awk 'NR==1 {print $1}' "$1" | tr -d '[:space:]'
}

# Atomically repoint a symlink via rename(2) (ln -sfn is unlink+create, not atomic).
repoint_current() {
  local target="$1"
  if [[ -e "${CURRENT_LINK}" && ! -L "${CURRENT_LINK}" ]]; then
    die "${CURRENT_LINK} exists and is not a symlink; remove it and retry"
  fi
  local tmp_link="${STATE_DIR}/.current.tmp.$$"
  rm -f "${tmp_link}"
  ln -s "${target}" "${tmp_link}"
  python3 - "${tmp_link}" "${CURRENT_LINK}" <<'PY'
import os
import sys

os.replace(sys.argv[1], sys.argv[2])
PY
}

# Smoke-test a bundle dir: start its stdio server and require a well-formed
# initialize response, so a broken bundle never becomes `current`.
smoke_bundle() {
  local bundle_dir="$1"
  local x07_exe="$2"
  X07_MCP_X07_EXE="${x07_exe}" python3 - "${bundle_dir}" <<'PY'
import json
import subprocess
import sys

bundle = sys.argv[1]
req = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-11-25", "capabilities": {},
               "clientInfo": {"name": "install-smoke", "version": "0"}},
})
p = subprocess.Popen(
    ["./server/x07lang-mcp"], cwd=bundle,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
)
try:
    out, _ = p.communicate(input=req + "\n", timeout=60)
except subprocess.TimeoutExpired:
    p.kill()
    out, _ = p.communicate()
for line in out.splitlines():
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    if msg.get("id") == 1 and "serverInfo" in (msg.get("result") or {}):
        sys.exit(0)
sys.exit(1)
PY
}

write_wrapper() {
  mkdir -p "${BIN_DIR}"
  # Always (re)write so wrapper fixes ship with every install. The wrapper
  # validates the x07 launcher up front instead of failing cryptically, and uses
  # the ambient launcher (it resolves the right toolchain per project).
  cat > "${WRAPPER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/.local/share/x07lang-mcp/current"
X07_EXE="${X07_MCP_X07_EXE:-$HOME/.x07/bin/x07}"
if [[ ! -x "${X07_EXE}" ]]; then
  echo "x07lang-mcp: x07 launcher not found or not executable: ${X07_EXE}" >&2
  echo "x07lang-mcp: install x07 via x07up, or set X07_MCP_X07_EXE to a valid x07 binary" >&2
  exit 1
fi
if [[ ! -x "${ROOT}/server/x07lang-mcp" ]]; then
  echo "x07lang-mcp: no current install at ${ROOT}; run install_local.sh" >&2
  exit 1
fi
cd "${ROOT}"
export X07_MCP_X07_EXE="${X07_EXE}"
exec "${ROOT}/server/x07lang-mcp" "$@"
EOF
  chmod +x "${WRAPPER}"
  echo "wrote ${WRAPPER}"
}

default_tag() {
  local version
  version="$(python3 - "${SERVER_ROOT}/x07.mcp.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)"
  printf 'x07lang-mcp-v%s\n' "${version}"
}

TAG=""
MCPB_PATH=""
UNINSTALL=0
ROLLBACK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --mcpb)
      [[ $# -ge 2 ]] || die "--mcpb requires a value"
      MCPB_PATH="$2"
      shift 2
      ;;
    --rollback)
      ROLLBACK=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

if [[ "${UNINSTALL}" == "1" ]]; then
  if [[ -e "${STATE_DIR}" || -L "${STATE_DIR}" ]]; then
    rm -rf "${STATE_DIR}"
    echo "removed ${STATE_DIR}"
  else
    echo "nothing to remove: ${STATE_DIR} does not exist"
  fi
  exit 0
fi

require_cmd python3

if [[ "${ROLLBACK}" == "1" ]]; then
  [[ -L "${CURRENT_LINK}" ]] || die "no current install to roll back from"
  current_target="$(readlink "${CURRENT_LINK}")"
  prev=""
  while IFS= read -r candidate; do
    [[ "${candidate}" == "${current_target}" ]] && continue
    prev="${candidate}"
    break
  done < <(ls -dt "${STATE_DIR}"/releases/*/bundle 2>/dev/null || true)
  [[ -n "${prev}" ]] || die "no previous release to roll back to under ${STATE_DIR}/releases"
  X07_EXE="${X07_MCP_X07_EXE:-${HOME}/.x07/bin/x07}"
  echo "smoke-testing rollback target ${prev}..."
  smoke_bundle "${prev}" "${X07_EXE}" || die "rollback target failed smoke-test: ${prev}"
  repoint_current "${prev}"
  write_wrapper
  echo "rolled back current -> ${prev}"
  exit 0
fi

require_cmd unzip

if [[ -z "${TAG}" ]]; then
  TAG="$(default_tag)"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

EXPECTED_SHA=""
if [[ -n "${MCPB_PATH}" ]]; then
  [[ -f "${MCPB_PATH}" ]] || die "no such file: ${MCPB_PATH}"
  BUNDLE_FILE="${MCPB_PATH}"
  if [[ -f "${MCPB_PATH}.sha256.txt" ]]; then
    EXPECTED_SHA="$(read_sha_file "${MCPB_PATH}.sha256.txt")"
  else
    echo "note: ${MCPB_PATH}.sha256.txt not found; skipping sha256 verification" >&2
  fi
else
  require_cmd curl
  BUNDLE_URL="${RELEASE_BASE_URL}/${TAG}/x07lang-mcp.mcpb"
  BUNDLE_FILE="${TMP_DIR}/x07lang-mcp.mcpb"
  echo "downloading ${BUNDLE_URL}"
  curl -fsSL -o "${BUNDLE_FILE}" "${BUNDLE_URL}" \
    || die "download failed: ${BUNDLE_URL}"
  curl -fsSL -o "${BUNDLE_FILE}.sha256.txt" "${BUNDLE_URL}.sha256.txt" \
    || die "download failed: ${BUNDLE_URL}.sha256.txt"
  EXPECTED_SHA="$(read_sha_file "${BUNDLE_FILE}.sha256.txt")"
fi

if [[ -n "${EXPECTED_SHA}" ]]; then
  [[ "${EXPECTED_SHA}" =~ ^[0-9a-f]{64}$ ]] \
    || die "malformed sha256 (want 64 lowercase hex chars): ${EXPECTED_SHA}"
  ACTUAL_SHA="$(sha256_of "${BUNDLE_FILE}")"
  if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
    die "sha256 mismatch for ${BUNDLE_FILE}: expected=${EXPECTED_SHA} actual=${ACTUAL_SHA}"
  fi
  echo "sha256 ok: ${ACTUAL_SHA}"
fi

BUNDLE_DIR="${STATE_DIR}/releases/${TAG}/bundle"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}"
unzip -qo "${BUNDLE_FILE}" -d "${BUNDLE_DIR}"
[[ -f "${BUNDLE_DIR}/server/x07lang-mcp" ]] \
  || die "bundle is missing server/x07lang-mcp: ${BUNDLE_FILE}"
chmod +x "${BUNDLE_DIR}/server/x07lang-mcp"
if [[ -f "${BUNDLE_DIR}/out/mcp-worker" ]]; then
  chmod +x "${BUNDLE_DIR}/out/mcp-worker"
fi

# Validate the x07 launcher and smoke-test the new bundle BEFORE making it
# current, so a broken bundle or missing toolchain never becomes the live server.
X07_EXE="${X07_MCP_X07_EXE:-${HOME}/.x07/bin/x07}"
[[ -x "${X07_EXE}" ]] \
  || die "x07 launcher not found or not executable: ${X07_EXE} (install x07 via x07up, or set X07_MCP_X07_EXE)"
echo "smoke-testing bundle..."
smoke_bundle "${BUNDLE_DIR}" "${X07_EXE}" \
  || die "bundle smoke-test failed (server did not answer initialize); not repointing current"
echo "smoke ok"

repoint_current "${BUNDLE_DIR}"
write_wrapper

echo "installed ${TAG} -> ${BUNDLE_DIR}"
echo "current -> $(readlink "${CURRENT_LINK}")"
echo
echo "Register with Claude Code:"
echo "  claude mcp add x07lang-mcp -s user -- ${HOME}/.local/share/x07lang-mcp/bin/x07lang-mcp-stdio"
