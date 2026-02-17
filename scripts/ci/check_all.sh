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
require_cmd jq

step "x07 version"
x07 --version

step "pkg lock (check)"
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  echo "skip root pkg.lock in local-deps mode"
else
  x07 pkg lock --project x07.json --check --offline >/dev/null
fi

step "external-packages lock (check)"
python3 scripts/generate_external_packages_lock.py --packages-root packages/ext --out locks/external-packages.lock --check >/dev/null

step "MCP pins (check)"
./scripts/ci/check_mcp_pins.sh >/dev/null

step "registry fixtures (check)"
./registry/scripts/check_fixtures.sh >/dev/null

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
  fs_dir="$x07_root/packages/ext/x07-ext-fs/0.1.4"
  data_model_dir="$x07_root/packages/ext/x07-ext-data-model/0.1.8"
  json_dir="$x07_root/packages/ext/x07-ext-json-rs/0.1.4"
  net_dir="$x07_root/packages/ext/x07-ext-net/0.1.8"
  stdio_dir="$x07_root/packages/ext/x07-ext-stdio/0.1.0"
  csv_dir="$x07_root/packages/ext/x07-ext-csv-rs/0.1.5"
  curl_dir="$x07_root/packages/ext/x07-ext-curl-c/0.1.6"
  ini_dir="$x07_root/packages/ext/x07-ext-ini-rs/0.1.4"
  sockets_dir="$x07_root/packages/ext/x07-ext-sockets-c/0.1.6"
  toml_dir="$x07_root/packages/ext/x07-ext-toml-rs/0.1.5"
  unicode_dir="$x07_root/packages/ext/x07-ext-unicode-rs/0.1.5"
  url_dir="$x07_root/packages/ext/x07-ext-url-rs/0.1.4"
  xml_dir="$x07_root/packages/ext/x07-ext-xml-rs/0.1.4"
  yaml_dir="$x07_root/packages/ext/x07-ext-yaml-rs/0.1.4"
  hex_dir="$x07_root/packages/ext/x07-ext-hex-rs/0.1.4"
  core_dir="$root/packages/ext/x07-ext-mcp-core/0.2.2"
  toolkit_dir="$root/packages/ext/x07-ext-mcp-toolkit/0.2.2"
  worker_dir="$root/packages/ext/x07-ext-mcp-worker/0.2.2"
  sandbox_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.2.2"
  transport_dir="$root/packages/ext/x07-ext-mcp-transport-stdio/0.2.2"
  auth_dir="$root/packages/ext/x07-ext-mcp-auth/0.1.0"
  obs_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.0"
  transport_http_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.2.0"
  rr_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.2"
  [[ -d "$jsonschema_dir" ]] || { echo "ERROR: missing local package: $jsonschema_dir" >&2; exit 2; }
  [[ -d "$fs_dir" ]] || { echo "ERROR: missing local package: $fs_dir" >&2; exit 2; }
  [[ -d "$data_model_dir" ]] || { echo "ERROR: missing local package: $data_model_dir" >&2; exit 2; }
  [[ -d "$json_dir" ]] || { echo "ERROR: missing local package: $json_dir" >&2; exit 2; }
  [[ -d "$net_dir" ]] || { echo "ERROR: missing local package: $net_dir" >&2; exit 2; }
  [[ -d "$stdio_dir" ]] || { echo "ERROR: missing local package: $stdio_dir" >&2; exit 2; }
  [[ -d "$csv_dir" ]] || { echo "ERROR: missing local package: $csv_dir" >&2; exit 2; }
  [[ -d "$curl_dir" ]] || { echo "ERROR: missing local package: $curl_dir" >&2; exit 2; }
  [[ -d "$ini_dir" ]] || { echo "ERROR: missing local package: $ini_dir" >&2; exit 2; }
  [[ -d "$sockets_dir" ]] || { echo "ERROR: missing local package: $sockets_dir" >&2; exit 2; }
  [[ -d "$toml_dir" ]] || { echo "ERROR: missing local package: $toml_dir" >&2; exit 2; }
  [[ -d "$unicode_dir" ]] || { echo "ERROR: missing local package: $unicode_dir" >&2; exit 2; }
  [[ -d "$url_dir" ]] || { echo "ERROR: missing local package: $url_dir" >&2; exit 2; }
  [[ -d "$xml_dir" ]] || { echo "ERROR: missing local package: $xml_dir" >&2; exit 2; }
  [[ -d "$yaml_dir" ]] || { echo "ERROR: missing local package: $yaml_dir" >&2; exit 2; }
  [[ -d "$hex_dir" ]] || { echo "ERROR: missing local package: $hex_dir" >&2; exit 2; }
  [[ -d "$core_dir" ]] || { echo "ERROR: missing local package: $core_dir" >&2; exit 2; }
  [[ -d "$toolkit_dir" ]] || { echo "ERROR: missing local package: $toolkit_dir" >&2; exit 2; }
  [[ -d "$worker_dir" ]] || { echo "ERROR: missing local package: $worker_dir" >&2; exit 2; }
  [[ -d "$sandbox_dir" ]] || { echo "ERROR: missing local package: $sandbox_dir" >&2; exit 2; }
  [[ -d "$transport_dir" ]] || { echo "ERROR: missing local package: $transport_dir" >&2; exit 2; }
  [[ -d "$auth_dir" ]] || { echo "ERROR: missing local package: $auth_dir" >&2; exit 2; }
  [[ -d "$obs_dir" ]] || { echo "ERROR: missing local package: $obs_dir" >&2; exit 2; }
  [[ -d "$transport_http_dir" ]] || { echo "ERROR: missing local package: $transport_http_dir" >&2; exit 2; }
  [[ -d "$rr_dir" ]] || { echo "ERROR: missing local package: $rr_dir" >&2; exit 2; }
  local_deps_dir=".x07/local"
  mkdir -p "$local_deps_dir"

  install_local_pkg() {
    local name="$1"
    local version="$2"
    local src="$3"
    local dst="$local_deps_dir/$name/$version"
    x07 pkg remove "$name" >/dev/null 2>&1 || true
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    x07 pkg add "$name@$version" --path "$dst" >/dev/null
  }

  install_local_pkg ext-jsonschema-rs 0.1.0 "$jsonschema_dir"
  install_local_pkg ext-fs 0.1.4 "$fs_dir"
  install_local_pkg ext-data-model 0.1.8 "$data_model_dir"
  install_local_pkg ext-json-rs 0.1.4 "$json_dir"
  install_local_pkg ext-net 0.1.8 "$net_dir"
  install_local_pkg ext-stdio 0.1.0 "$stdio_dir"
  install_local_pkg ext-csv-rs 0.1.5 "$csv_dir"
  install_local_pkg ext-curl-c 0.1.6 "$curl_dir"
  install_local_pkg ext-ini-rs 0.1.4 "$ini_dir"
  install_local_pkg ext-sockets-c 0.1.6 "$sockets_dir"
  install_local_pkg ext-toml-rs 0.1.5 "$toml_dir"
  install_local_pkg ext-unicode-rs 0.1.5 "$unicode_dir"
  install_local_pkg ext-url-rs 0.1.4 "$url_dir"
  install_local_pkg ext-xml-rs 0.1.4 "$xml_dir"
  install_local_pkg ext-yaml-rs 0.1.4 "$yaml_dir"
  install_local_pkg ext-hex-rs 0.1.4 "$hex_dir"
  install_local_pkg ext-mcp-core 0.2.2 "$core_dir"
  install_local_pkg ext-mcp-toolkit 0.2.2 "$toolkit_dir"
  install_local_pkg ext-mcp-worker 0.2.2 "$worker_dir"
  install_local_pkg ext-mcp-sandbox 0.2.2 "$sandbox_dir"
  install_local_pkg ext-mcp-transport-stdio 0.2.2 "$transport_dir"
  install_local_pkg ext-mcp-auth 0.1.0 "$auth_dir"
  install_local_pkg ext-mcp-obs 0.1.0 "$obs_dir"
  install_local_pkg ext-mcp-transport-http 0.2.0 "$transport_http_dir"
  install_local_pkg ext-mcp-rr 0.2.2 "$rr_dir"
  x07 pkg lock --project x07.json --offline >/dev/null
else
  x07 pkg add ext-mcp-transport-stdio@0.2.2 --sync >/dev/null
  x07 pkg add ext-mcp-rr@0.2.2 --sync >/dev/null
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
  x07_root="$(cd "$root/../x07" && pwd)"
  jsonschema_dir="$x07_root/packages/ext/x07-ext-jsonschema-rs/0.1.0"
  fs_dir="$x07_root/packages/ext/x07-ext-fs/0.1.4"
  data_model_dir="$x07_root/packages/ext/x07-ext-data-model/0.1.8"
  json_dir="$x07_root/packages/ext/x07-ext-json-rs/0.1.4"
  net_dir="$x07_root/packages/ext/x07-ext-net/0.1.8"
  stdio_dir="$x07_root/packages/ext/x07-ext-stdio/0.1.0"
  csv_dir="$x07_root/packages/ext/x07-ext-csv-rs/0.1.5"
  curl_dir="$x07_root/packages/ext/x07-ext-curl-c/0.1.6"
  ini_dir="$x07_root/packages/ext/x07-ext-ini-rs/0.1.4"
  sockets_dir="$x07_root/packages/ext/x07-ext-sockets-c/0.1.6"
  toml_dir="$x07_root/packages/ext/x07-ext-toml-rs/0.1.5"
  unicode_dir="$x07_root/packages/ext/x07-ext-unicode-rs/0.1.5"
  url_dir="$x07_root/packages/ext/x07-ext-url-rs/0.1.4"
  xml_dir="$x07_root/packages/ext/x07-ext-xml-rs/0.1.4"
  yaml_dir="$x07_root/packages/ext/x07-ext-yaml-rs/0.1.4"
  core_http_dir="$root/packages/ext/x07-ext-mcp-core/0.2.2"
  toolkit_http_dir="$root/packages/ext/x07-ext-mcp-toolkit/0.2.2"
  worker_http_dir="$root/packages/ext/x07-ext-mcp-worker/0.2.2"
  sandbox_http_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.2.2"
  auth_http_dir="$root/packages/ext/x07-ext-mcp-auth/0.1.0"
  obs_http_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.0"
  transport_http_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.2.0"
  rr_http_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.2"
  [[ -d "$jsonschema_dir" ]] || { echo "ERROR: missing local package: $jsonschema_dir" >&2; exit 2; }
  [[ -d "$fs_dir" ]] || { echo "ERROR: missing local package: $fs_dir" >&2; exit 2; }
  [[ -d "$data_model_dir" ]] || { echo "ERROR: missing local package: $data_model_dir" >&2; exit 2; }
  [[ -d "$json_dir" ]] || { echo "ERROR: missing local package: $json_dir" >&2; exit 2; }
  [[ -d "$net_dir" ]] || { echo "ERROR: missing local package: $net_dir" >&2; exit 2; }
  [[ -d "$stdio_dir" ]] || { echo "ERROR: missing local package: $stdio_dir" >&2; exit 2; }
  [[ -d "$csv_dir" ]] || { echo "ERROR: missing local package: $csv_dir" >&2; exit 2; }
  [[ -d "$curl_dir" ]] || { echo "ERROR: missing local package: $curl_dir" >&2; exit 2; }
  [[ -d "$ini_dir" ]] || { echo "ERROR: missing local package: $ini_dir" >&2; exit 2; }
  [[ -d "$sockets_dir" ]] || { echo "ERROR: missing local package: $sockets_dir" >&2; exit 2; }
  [[ -d "$toml_dir" ]] || { echo "ERROR: missing local package: $toml_dir" >&2; exit 2; }
  [[ -d "$unicode_dir" ]] || { echo "ERROR: missing local package: $unicode_dir" >&2; exit 2; }
  [[ -d "$url_dir" ]] || { echo "ERROR: missing local package: $url_dir" >&2; exit 2; }
  [[ -d "$xml_dir" ]] || { echo "ERROR: missing local package: $xml_dir" >&2; exit 2; }
  [[ -d "$yaml_dir" ]] || { echo "ERROR: missing local package: $yaml_dir" >&2; exit 2; }
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
    x07 pkg remove "$name" >/dev/null 2>&1 || true
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    x07 pkg add "$name@$version" --path "$dst" >/dev/null
  }

  install_local_pkg ext-jsonschema-rs 0.1.0 "$jsonschema_dir"
  install_local_pkg ext-fs 0.1.4 "$fs_dir"
  install_local_pkg ext-data-model 0.1.8 "$data_model_dir"
  install_local_pkg ext-json-rs 0.1.4 "$json_dir"
  install_local_pkg ext-net 0.1.8 "$net_dir"
  install_local_pkg ext-stdio 0.1.0 "$stdio_dir"
  install_local_pkg ext-csv-rs 0.1.5 "$csv_dir"
  install_local_pkg ext-curl-c 0.1.6 "$curl_dir"
  install_local_pkg ext-ini-rs 0.1.4 "$ini_dir"
  install_local_pkg ext-sockets-c 0.1.6 "$sockets_dir"
  install_local_pkg ext-toml-rs 0.1.5 "$toml_dir"
  install_local_pkg ext-unicode-rs 0.1.5 "$unicode_dir"
  install_local_pkg ext-url-rs 0.1.4 "$url_dir"
  install_local_pkg ext-xml-rs 0.1.4 "$xml_dir"
  install_local_pkg ext-yaml-rs 0.1.4 "$yaml_dir"
  install_local_pkg ext-mcp-core 0.2.2 "$core_http_dir"
  install_local_pkg ext-mcp-toolkit 0.2.2 "$toolkit_http_dir"
  install_local_pkg ext-mcp-worker 0.2.2 "$worker_http_dir"
  install_local_pkg ext-mcp-sandbox 0.2.2 "$sandbox_http_dir"
  install_local_pkg ext-mcp-auth 0.1.0 "$auth_http_dir"
  install_local_pkg ext-mcp-obs 0.1.0 "$obs_http_dir"
  install_local_pkg ext-mcp-transport-http 0.2.0 "$transport_http_dir"
  install_local_pkg ext-mcp-rr 0.2.2 "$rr_http_dir"
  x07 pkg lock --project x07.json --offline >/dev/null
else
  x07 pkg add ext-mcp-transport-http@0.2.0 --sync >/dev/null
  x07 pkg add ext-mcp-rr@0.2.2 --sync >/dev/null
fi
x07 test --manifest tests/tests.json >/dev/null

echo
echo "ok: all checks passed"
