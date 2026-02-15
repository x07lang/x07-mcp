#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

root="$(repo_root)"
cd "$root"

step() {
  echo
  echo "==> $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 2
  fi
}

require_cmd x07
require_cmd python3

step "x07 version"
x07 --version

step "pkg lock (check)"
x07 pkg lock --project x07.json --check --offline >/dev/null

step "external-packages lock (check)"
python3 scripts/generate_external_packages_lock.py --packages-root packages/ext --out locks/external-packages.lock --check >/dev/null

step "fmt check (x07AST JSON)"
while IFS= read -r -d '' f; do
  x07 fmt --input "$f" --check --report-json >/dev/null
done < <(find cli/src packages/ext templates -type f -name '*.x07.json' -print0)

step "bundle x07-mcp"
mkdir -p dist
x07 bundle --project x07.json --profile os --out dist/x07-mcp >/dev/null
./dist/x07-mcp --help >/dev/null

step "scaffold e2e (mcp-server-stdio)"
tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

proj_rel="proj"
(
  cd "$tmp"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-stdio --dir "$proj_rel" --machine json >"$tmp/report.json"
)
proj="$tmp/$proj_rel"
python3 - "$tmp/report.json" <<'PY'
import json
import sys

path = sys.argv[1]
doc = json.load(open(path, "r", encoding="utf-8"))
if not doc.get("ok"):
    raise SystemExit(f"scaffold report not ok: {doc!r}")
PY

cd "$proj"

step "template deps + tests"
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  x07_root="$(cd "$root/../x07" && pwd)"
  jsonschema_dir="$x07_root/packages/ext/x07-ext-jsonschema-rs/0.1.0"
  core_dir="$root/packages/ext/x07-ext-mcp-core/0.2.0"
  toolkit_dir="$root/packages/ext/x07-ext-mcp-toolkit/0.2.0"
  worker_dir="$root/packages/ext/x07-ext-mcp-worker/0.2.0"
  sandbox_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.2.0"
  transport_dir="$root/packages/ext/x07-ext-mcp-transport-stdio/0.2.0"
  rr_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.0"
  [[ -d "$jsonschema_dir" ]] || { echo "ERROR: missing local package: $jsonschema_dir" >&2; exit 2; }
  [[ -d "$core_dir" ]] || { echo "ERROR: missing local package: $core_dir" >&2; exit 2; }
  [[ -d "$toolkit_dir" ]] || { echo "ERROR: missing local package: $toolkit_dir" >&2; exit 2; }
  [[ -d "$worker_dir" ]] || { echo "ERROR: missing local package: $worker_dir" >&2; exit 2; }
  [[ -d "$sandbox_dir" ]] || { echo "ERROR: missing local package: $sandbox_dir" >&2; exit 2; }
  [[ -d "$transport_dir" ]] || { echo "ERROR: missing local package: $transport_dir" >&2; exit 2; }
  [[ -d "$rr_dir" ]] || { echo "ERROR: missing local package: $rr_dir" >&2; exit 2; }
  local_deps_dir=".x07/local"
  mkdir -p "$local_deps_dir"

  install_local_pkg() {
    local name="$1"
    local version="$2"
    local src="$3"
    local dst="$local_deps_dir/$name/$version"
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    x07 pkg add "$name@$version" --path "$dst" >/dev/null
  }

  install_local_pkg ext-jsonschema-rs 0.1.0 "$jsonschema_dir"
  install_local_pkg ext-mcp-core 0.2.0 "$core_dir"
  install_local_pkg ext-mcp-toolkit 0.2.0 "$toolkit_dir"
  install_local_pkg ext-mcp-worker 0.2.0 "$worker_dir"
  install_local_pkg ext-mcp-sandbox 0.2.0 "$sandbox_dir"
  install_local_pkg ext-mcp-transport-stdio 0.2.0 "$transport_dir"
  install_local_pkg ext-mcp-rr 0.2.0 "$rr_dir"
  x07 pkg add ext-hex-rs@0.1.4 >/dev/null
  x07 pkg lock --project x07.json --offline >/dev/null
else
  x07 pkg add ext-mcp-transport-stdio@0.2.0 --sync >/dev/null
  x07 pkg add ext-mcp-rr@0.2.0 --sync >/dev/null
  x07 pkg add ext-hex-rs@0.1.4 --sync >/dev/null
fi
x07 arch check --manifest arch/manifest.x07arch.json --lock arch/manifest.lock.json >/dev/null
x07 test --manifest tests/tests.json >/dev/null

step "scaffold e2e (mcp-server-http)"
tmp_http="$(mktemp -d)"
cleanup_http() { rm -rf "$tmp_http"; }
trap cleanup_http EXIT

proj_http_rel="proj-http"
(
  cd "$tmp_http"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-http --dir "$proj_http_rel" --machine json >"$tmp_http/report.json"
)
proj_http="$tmp_http/$proj_http_rel"
python3 - "$tmp_http/report.json" <<'PY'
import json
import sys

path = sys.argv[1]
doc = json.load(open(path, "r", encoding="utf-8"))
if not doc.get("ok"):
    raise SystemExit(f"scaffold report not ok: {doc!r}")
PY

cd "$proj_http"

if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  core_http_dir="$root/packages/ext/x07-ext-mcp-core/0.2.0"
  toolkit_http_dir="$root/packages/ext/x07-ext-mcp-toolkit/0.2.0"
  worker_http_dir="$root/packages/ext/x07-ext-mcp-worker/0.2.0"
  sandbox_http_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.2.0"
  auth_http_dir="$root/packages/ext/x07-ext-mcp-auth/0.1.0"
  obs_http_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.0"
  transport_http_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.1.0"
  rr_http_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.0"
  [[ -d "$core_http_dir" ]] || { echo "ERROR: missing local package: $core_http_dir" >&2; exit 2; }
  [[ -d "$toolkit_http_dir" ]] || { echo "ERROR: missing local package: $toolkit_http_dir" >&2; exit 2; }
  [[ -d "$worker_http_dir" ]] || { echo "ERROR: missing local package: $worker_http_dir" >&2; exit 2; }
  [[ -d "$sandbox_http_dir" ]] || { echo "ERROR: missing local package: $sandbox_http_dir" >&2; exit 2; }
  [[ -d "$auth_http_dir" ]] || { echo "ERROR: missing local package: $auth_http_dir" >&2; exit 2; }
  [[ -d "$obs_http_dir" ]] || { echo "ERROR: missing local package: $obs_http_dir" >&2; exit 2; }
  [[ -d "$transport_http_dir" ]] || { echo "ERROR: missing local package: $transport_http_dir" >&2; exit 2; }
  [[ -d "$rr_http_dir" ]] || { echo "ERROR: missing local package: $rr_http_dir" >&2; exit 2; }
  local_deps_dir=".x07/local"
  mkdir -p "$local_deps_dir"

  install_local_pkg() {
    local name="$1"
    local version="$2"
    local src="$3"
    local dst="$local_deps_dir/$name/$version"
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    x07 pkg add "$name@$version" --path "$dst" >/dev/null
  }

  install_local_pkg ext-mcp-core 0.2.0 "$core_http_dir"
  install_local_pkg ext-mcp-toolkit 0.2.0 "$toolkit_http_dir"
  install_local_pkg ext-mcp-worker 0.2.0 "$worker_http_dir"
  install_local_pkg ext-mcp-sandbox 0.2.0 "$sandbox_http_dir"
  install_local_pkg ext-mcp-auth 0.1.0 "$auth_http_dir"
  install_local_pkg ext-mcp-obs 0.1.0 "$obs_http_dir"
  install_local_pkg ext-mcp-transport-http 0.1.0 "$transport_http_dir"
  install_local_pkg ext-mcp-rr 0.2.0 "$rr_http_dir"
  x07 pkg lock --project x07.json --offline >/dev/null
else
  x07 pkg add ext-mcp-transport-http@0.1.0 --sync >/dev/null
  x07 pkg add ext-mcp-rr@0.2.0 --sync >/dev/null
fi
x07 test --manifest tests/tests.json >/dev/null

echo
echo "ok: all checks passed"
