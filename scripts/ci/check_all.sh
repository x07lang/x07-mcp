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

tmp_dirs=()
cleanup() {
  for d in "${tmp_dirs[@]:-}"; do
    rm -rf "$d" || true
  done
}
trap cleanup EXIT

workspace_x07_root() {
  cd "$root/../x07" && pwd
}

install_project_local_deps_from_workspace() {
  local x07_root="$1"
  local project_dir="$2"

  (
    cd "$project_dir"
    local local_deps_dir=".x07/local"
    mkdir -p "$local_deps_dir"

    while IFS=$'\t' read -r name version; do
      [[ -n "$name" && -n "$version" ]] || continue

      local src="$root/packages/ext/x07-$name/$version"
      if [[ ! -d "$src" ]]; then
        src="$x07_root/packages/ext/x07-$name/$version"
      fi
      [[ -d "$src" ]] || { echo "ERROR: missing local package: $name@$version (expected: $src)" >&2; exit 2; }

      x07 pkg remove "$name" >/dev/null 2>&1 || true
      local dst="$local_deps_dir/$name/$version"
      rm -rf "$dst"
      mkdir -p "$(dirname "$dst")"
      cp -R "$src" "$dst"
      x07 pkg add "$name@$version" --path "$dst" >/dev/null
    done < <(jq -r '.dependencies[] | "\(.name)\t\(.version)"' x07.json)
  )
}

step "x07 version"
x07 --version

step "pkg lock (hydrate + check)"
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  echo "skip root pkg.lock in local-deps mode"
else
  ./scripts/ci/hydrate_root_deps.sh
  x07 pkg lock --project x07.json --check --offline >/dev/null
fi

step "external-packages lock (check)"
python3 scripts/generate_external_packages_lock.py --packages-root packages/ext --out locks/external-packages.lock --check >/dev/null

step "latest pins + schemas (check)"
python3 scripts/ci/check_latest_pins.py >/dev/null

step "MCP pins (check)"
./scripts/ci/check_mcp_pins.sh >/dev/null

step "registry fixtures (check)"
./registry/scripts/check_fixtures.sh

step "fmt check (x07AST JSON)"
while IFS= read -r -d '' f; do
  x07 fmt --input "$f" --check --report-json >/dev/null
done < <(
  find cli/src packages/ext templates conformance/client-x07/src conformance/client-x07/tests \
    -type d -name .x07 -prune -o \
    -type f -name '*.x07.json' -print0
)

step "schema version check (x07ast)"
x07ast_schema="$(x07 ast schema --json=off | jq -r '.properties.schema_version.const')"
[[ -n "$x07ast_schema" ]] || { echo "ERROR: failed to read x07ast schema_version const" >&2; exit 2; }
while IFS= read -r -d '' f; do
  got="$(jq -r '.schema_version // empty' "$f")"
  if [[ "$got" != "$x07ast_schema" ]]; then
    echo "ERROR: x07ast schema_version drift: $f (got=$got want=$x07ast_schema)" >&2
    exit 2
  fi
done < <(
  find cli/src templates conformance/client-x07/src conformance/client-x07/tests servers \
    -type d -name .x07 -prune -o \
    -type f -name '*.x07.json' -print0
)

step "cli template assets (check)"
assets_tmp="$(mktemp -d)"
tmp_dirs+=("$assets_tmp")

check_asset() {
  local template="$1"
  local module_id="$2"
  local out_path="$3"
  local gen_path="$assets_tmp/$(basename "$out_path")"

  python3 scripts/generate_cli_template_asset_module.py \
    --template-dir "templates/$template" \
    --module-id "$module_id" \
    --out "$gen_path" \
    >/dev/null

  if ! cmp -s "$gen_path" "$out_path"; then
    echo "ERROR: cli asset module out of date: $out_path (template=templates/$template)" >&2
    echo "Hint: run:" >&2
    echo "  python3 scripts/generate_cli_template_asset_module.py --template-dir templates/$template --module-id $module_id --out $out_path" >&2
    exit 2
  fi
}

check_asset shared x07.mcp.cli.assets.shared cli/src/x07/mcp/cli/assets/shared.x07.json
check_asset mcp-server x07.mcp.cli.assets.mcp-server cli/src/x07/mcp/cli/assets/mcp-server.x07.json
check_asset mcp-server-stdio x07.mcp.cli.assets.mcp-server-stdio cli/src/x07/mcp/cli/assets/mcp-server-stdio.x07.json
check_asset mcp-server-http x07.mcp.cli.assets.mcp-server-http cli/src/x07/mcp/cli/assets/mcp-server-http.x07.json
check_asset mcp-server-http-tasks x07.mcp.cli.assets.mcp-server-http-tasks cli/src/x07/mcp/cli/assets/mcp-server-http-tasks.x07.json

step "lint check (publish ext package modules)"
lint_dirs=(
  "packages/app/x07-mcp/0.1.0/modules"
  "packages/app/x07-mcp/0.2.0/modules"
  "packages/ext/x07-ext-mcp-auth-core/0.1.0/modules"
  "packages/ext/x07-ext-mcp-auth-core/0.1.1/modules"
  "packages/ext/x07-ext-mcp-auth/0.2.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.3.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.3.1/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.1/modules"
  "packages/ext/x07-ext-mcp-core/0.3.2/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.1/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.2/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.3/modules"
  "packages/ext/x07-ext-mcp-rr/0.2.3/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.2/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.3/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.4/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.5/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.6/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.7/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.8/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.9/modules"
  "packages/ext/x07-ext-mcp-sandbox/0.3.2/modules"
  "packages/ext/x07-ext-mcp-sandbox/0.3.3/modules"
  "packages/ext/x07-ext-mcp-toolkit/0.3.2/modules"
  "packages/ext/x07-ext-mcp-toolkit/0.3.3/modules"
  "packages/ext/x07-ext-mcp-trust/0.1.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.2.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.3.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.1.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.3.0/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.2.1/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.2/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.3/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.4/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.5/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.6/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.7/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.8/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.9/modules"
  "packages/ext/x07-ext-mcp-worker/0.3.2/modules"
  "packages/ext/x07-ext-mcp-worker/0.3.3/modules"
)
for d in "${lint_dirs[@]}"; do
  [[ -d "$d" ]] || { echo "ERROR: missing lint dir: $d" >&2; exit 2; }
done
while IFS= read -r -d '' f; do
  x07 lint --input "$f" >/dev/null
done < <(find "${lint_dirs[@]}" -type f -name '*.x07.json' -print0)

step "package tests (ext-mcp-rr sanitizer)"
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  x07_root="$(cd "$root/../x07" && pwd)"
  auth_jwt_modules="$x07_root/packages/ext/x07-ext-auth-jwt/0.1.4/modules"
  base64_modules="$x07_root/packages/ext/x07-ext-base64-rs/0.1.4/modules"
  crypto_modules="$x07_root/packages/ext/x07-ext-crypto-rs/0.1.4/modules"
  curl_modules="$x07_root/packages/ext/x07-ext-curl-c/0.1.6/modules"
  data_model_modules="$x07_root/packages/ext/x07-ext-data-model/0.1.8/modules"
  db_core_modules="$x07_root/packages/ext/x07-ext-db-core/0.1.9/modules"
  db_sqlite_modules="$x07_root/packages/ext/x07-ext-db-sqlite/0.1.9/modules"
  fs_modules="$x07_root/packages/ext/x07-ext-fs/0.1.5/modules"
  hex_modules="$x07_root/packages/ext/x07-ext-hex-rs/0.1.4/modules"
  json_modules="$x07_root/packages/ext/x07-ext-json-rs/0.1.4/modules"
  jsonschema_modules="$x07_root/packages/ext/x07-ext-jsonschema-rs/0.1.0/modules"
  math_modules="$x07_root/packages/ext/x07-ext-math/0.1.4/modules"
  net_modules="$x07_root/packages/ext/x07-ext-net/0.1.9/modules"
  obs_ext_modules="$x07_root/packages/ext/x07-ext-obs/0.1.2/modules"
  openssl_modules="$x07_root/packages/ext/x07-ext-openssl-c/0.1.8/modules"
  pb_modules="$x07_root/packages/ext/x07-ext-pb-rs/0.1.5/modules"
  rand_modules="$x07_root/packages/ext/x07-ext-rand/0.1.0/modules"
  regex_modules="$x07_root/packages/ext/x07-ext-regex/0.2.4/modules"
  sockets_modules="$x07_root/packages/ext/x07-ext-sockets-c/0.1.6/modules"
  stdio_modules="$x07_root/packages/ext/x07-ext-stdio/0.1.0/modules"
  time_modules="$x07_root/packages/ext/x07-ext-time-rs/0.1.5/modules"
  u64_modules="$x07_root/packages/ext/x07-ext-u64-rs/0.1.4/modules"
  unicode_modules="$x07_root/packages/ext/x07-ext-unicode-rs/0.1.5/modules"
  url_modules="$x07_root/packages/ext/x07-ext-url-rs/0.1.4/modules"
  [[ -d "$auth_jwt_modules" ]] || { echo "ERROR: missing local modules: $auth_jwt_modules" >&2; exit 2; }
  [[ -d "$data_model_modules" ]] || { echo "ERROR: missing local modules: $data_model_modules" >&2; exit 2; }
  [[ -d "$db_core_modules" ]] || { echo "ERROR: missing local modules: $db_core_modules" >&2; exit 2; }
  [[ -d "$db_sqlite_modules" ]] || { echo "ERROR: missing local modules: $db_sqlite_modules" >&2; exit 2; }
  [[ -d "$fs_modules" ]] || { echo "ERROR: missing local modules: $fs_modules" >&2; exit 2; }
  [[ -d "$json_modules" ]] || { echo "ERROR: missing local modules: $json_modules" >&2; exit 2; }
  [[ -d "$jsonschema_modules" ]] || { echo "ERROR: missing local modules: $jsonschema_modules" >&2; exit 2; }
  [[ -d "$math_modules" ]] || { echo "ERROR: missing local modules: $math_modules" >&2; exit 2; }
  [[ -d "$regex_modules" ]] || { echo "ERROR: missing local modules: $regex_modules" >&2; exit 2; }
  [[ -d "$unicode_modules" ]] || { echo "ERROR: missing local modules: $unicode_modules" >&2; exit 2; }
  [[ -d "$base64_modules" ]] || { echo "ERROR: missing local modules: $base64_modules" >&2; exit 2; }
  [[ -d "$crypto_modules" ]] || { echo "ERROR: missing local modules: $crypto_modules" >&2; exit 2; }
  [[ -d "$curl_modules" ]] || { echo "ERROR: missing local modules: $curl_modules" >&2; exit 2; }
  [[ -d "$hex_modules" ]] || { echo "ERROR: missing local modules: $hex_modules" >&2; exit 2; }
  [[ -d "$net_modules" ]] || { echo "ERROR: missing local modules: $net_modules" >&2; exit 2; }
  [[ -d "$obs_ext_modules" ]] || { echo "ERROR: missing local modules: $obs_ext_modules" >&2; exit 2; }
  [[ -d "$openssl_modules" ]] || { echo "ERROR: missing local modules: $openssl_modules" >&2; exit 2; }
  [[ -d "$pb_modules" ]] || { echo "ERROR: missing local modules: $pb_modules" >&2; exit 2; }
  [[ -d "$rand_modules" ]] || { echo "ERROR: missing local modules: $rand_modules" >&2; exit 2; }
  [[ -d "$time_modules" ]] || { echo "ERROR: missing local modules: $time_modules" >&2; exit 2; }
  [[ -d "$sockets_modules" ]] || { echo "ERROR: missing local modules: $sockets_modules" >&2; exit 2; }
  [[ -d "$stdio_modules" ]] || { echo "ERROR: missing local modules: $stdio_modules" >&2; exit 2; }
  [[ -d "$u64_modules" ]] || { echo "ERROR: missing local modules: $u64_modules" >&2; exit 2; }
  [[ -d "$url_modules" ]] || { echo "ERROR: missing local modules: $url_modules" >&2; exit 2; }

  step "package tests (ext-mcp-auth-core)"
  auth_core_011_dir="$root/packages/ext/x07-ext-mcp-auth-core/0.1.1"
  [[ -d "$auth_core_011_dir" ]] || { echo "ERROR: missing local package: $auth_core_011_dir" >&2; exit 2; }
  (
    cd "$auth_core_011_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-trust)"
  trust_010_dir="$root/packages/ext/x07-ext-mcp-trust/0.1.0"
  [[ -d "$trust_010_dir" ]] || { echo "ERROR: missing local package: $trust_010_dir" >&2; exit 2; }
  (
    cd "$trust_010_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-trust@0.2.0)"
  trust_020_dir="$root/packages/ext/x07-ext-mcp-trust/0.2.0"
  [[ -d "$trust_020_dir" ]] || { echo "ERROR: missing local package: $trust_020_dir" >&2; exit 2; }
  (
    cd "$trust_020_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-trust@0.3.0)"
  trust_030_dir="$root/packages/ext/x07-ext-mcp-trust/0.3.0"
  [[ -d "$trust_030_dir" ]] || { echo "ERROR: missing local package: $trust_030_dir" >&2; exit 2; }
  (
    cd "$trust_030_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-trust-os@0.1.0)"
  trust_os_010_dir="$root/packages/ext/x07-ext-mcp-trust-os/0.1.0"
  [[ -d "$trust_os_010_dir" ]] || { echo "ERROR: missing local package: $trust_os_010_dir" >&2; exit 2; }
  (
    cd "$trust_os_010_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$net_modules" \
      --module-root "$url_modules" \
      --module-root "$json_modules" \
      --module-root "$data_model_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-trust-os@0.3.0)"
  trust_os_030_dir="$root/packages/ext/x07-ext-mcp-trust-os/0.3.0"
  [[ -d "$trust_os_030_dir" ]] || { echo "ERROR: missing local package: $trust_os_030_dir" >&2; exit 2; }
  (
    cd "$trust_os_030_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_030_dir/modules" \
      --module-root "$net_modules" \
      --module-root "$url_modules" \
      --module-root "$json_modules" \
      --module-root "$data_model_modules" \
      --module-root "$crypto_modules" \
      --module-root "$hex_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      --module-root "$curl_modules" \
      >/dev/null
  )

  step "package tests (x07-mcp publish trust modules)"
  app_pkg_010_dir="$root/packages/app/x07-mcp/0.1.0"
  [[ -d "$app_pkg_010_dir" ]] || { echo "ERROR: missing local package: $app_pkg_010_dir" >&2; exit 2; }
  (
    cd "$app_pkg_010_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_010_dir/modules" \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (x07-mcp@0.2.0 publish trust modules)"
  app_pkg_020_dir="$root/packages/app/x07-mcp/0.2.0"
  [[ -d "$app_pkg_020_dir" ]] || { echo "ERROR: missing local package: $app_pkg_020_dir" >&2; exit 2; }
  (
    cd "$app_pkg_020_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_030_dir/modules" \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  rr_023_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.3"
  rr_033_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.3"
  rr_034_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.4"
  rr_037_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.7"
  rr_038_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.8"
  rr_039_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.9"
  [[ -d "$rr_023_dir" ]] || { echo "ERROR: missing local package: $rr_023_dir" >&2; exit 2; }
  [[ -d "$rr_033_dir" ]] || { echo "ERROR: missing local package: $rr_033_dir" >&2; exit 2; }
  [[ -d "$rr_034_dir" ]] || { echo "ERROR: missing local package: $rr_034_dir" >&2; exit 2; }
  [[ -d "$rr_037_dir" ]] || { echo "ERROR: missing local package: $rr_037_dir" >&2; exit 2; }
  [[ -d "$rr_038_dir" ]] || { echo "ERROR: missing local package: $rr_038_dir" >&2; exit 2; }
  [[ -d "$rr_039_dir" ]] || { echo "ERROR: missing local package: $rr_039_dir" >&2; exit 2; }

  (
    cd "$rr_023_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.2.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.0/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.2.0/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$jsonschema_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$rr_033_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.0/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.2.0/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$rr_034_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.3.0/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$rr_037_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.3.1/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$rr_038_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.0/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$rr_039_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.1/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-auth)"
  auth_020_dir="$root/packages/ext/x07-ext-mcp-auth/0.2.0"
  auth_030_dir="$root/packages/ext/x07-ext-mcp-auth/0.3.0"
  auth_031_dir="$root/packages/ext/x07-ext-mcp-auth/0.3.1"
  auth_040_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.0"
  auth_041_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.1"
  [[ -d "$auth_020_dir" ]] || { echo "ERROR: missing local package: $auth_020_dir" >&2; exit 2; }
  [[ -d "$auth_030_dir" ]] || { echo "ERROR: missing local package: $auth_030_dir" >&2; exit 2; }
  [[ -d "$auth_031_dir" ]] || { echo "ERROR: missing local package: $auth_031_dir" >&2; exit 2; }
  [[ -d "$auth_040_dir" ]] || { echo "ERROR: missing local package: $auth_040_dir" >&2; exit 2; }
  [[ -d "$auth_041_dir" ]] || { echo "ERROR: missing local package: $auth_041_dir" >&2; exit 2; }
  (
    cd "$auth_020_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.0/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$auth_030_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$db_core_modules" \
      --module-root "$db_sqlite_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$jsonschema_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$auth_031_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$auth_040_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  (
    cd "$auth_041_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$net_modules" \
      --module-root "$sockets_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-obs)"
  obs_013_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.3"
  [[ -d "$obs_013_dir" ]] || { echo "ERROR: missing local package: $obs_013_dir" >&2; exit 2; }
  (
    cd "$obs_013_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root tests \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$fs_modules" \
      --module-root "$net_modules" \
      --module-root "$obs_ext_modules" \
      --module-root "$stdio_modules" \
      --module-root "$unicode_modules" \
      --module-root "$curl_modules" \
      --module-root "$pb_modules" \
      --module-root "$u64_modules" \
      --module-root "$math_modules" \
      >/dev/null
  )

  step "package tests (ext-mcp-sandbox)"
  sandbox_033_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.3.3"
  [[ -d "$sandbox_033_dir" ]] || { echo "ERROR: missing local package: $sandbox_033_dir" >&2; exit 2; }
  (
    cd "$sandbox_033_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.3/modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$stdio_modules" \
      --module-root "$unicode_modules" \
      >/dev/null

    # x07 test entrypoints are synchronous (`result_i32`/status-bytes), so keep
    # the async router stream deadlock regression as an explicit run-os smoke.
    stream_smoke_json="$(
      (
        cd tests
        x07-os-runner \
          --program router_exec_streaming_deadlock_entry.x07.json \
          --world run-os \
          --module-root ../modules \
          --module-root . \
          --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.3/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.3/modules" \
          --module-root "$data_model_modules" \
          --module-root "$json_modules" \
          --module-root "$stdio_modules" \
          --module-root "$unicode_modules" \
          --auto-ffi
      )
    )"
    stream_smoke_ok="$(printf '%s' "$stream_smoke_json" | jq -r '.solve.ok // false')"
    stream_smoke_out="$(printf '%s' "$stream_smoke_json" | jq -r '(.solve.solve_output_b64 // "") | @base64d')"
    if [[ "$stream_smoke_ok" != "true" || "$stream_smoke_out" != "ok" ]]; then
      echo "ERROR: ext-mcp-sandbox streaming deadlock regression failed (ok=$stream_smoke_ok out=$stream_smoke_out)" >&2
      echo "$stream_smoke_json" >&2
      exit 2
    fi
  )

  step "package tests (ext-mcp-transport-http)"
  transport_http_039_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.3.9"
  [[ -d "$transport_http_039_dir" ]] || { echo "ERROR: missing local package: $transport_http_039_dir" >&2; exit 2; }
  (
    cd "$transport_http_039_dir"
    # `x07 test --manifest tests/tests.json` runs with CWD=`tests/`, so the socket-level
    # smoke test expects the compiled server solver under `tests/target/...`.
    mkdir -p tests/target/x07test/transport_http_server_smoke
    x07-os-runner \
      --program tests/socket_server_main.x07.json \
      --compiled-out tests/target/x07test/transport_http_server_smoke/socket_server_solver \
      --compile-only \
      --module-root modules \
      --module-root tests \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-sandbox/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-obs/0.1.3/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$db_core_modules" \
      --module-root "$db_sqlite_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$jsonschema_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      --module-root "$pb_modules" \
      --module-root "$u64_modules" \
      --module-root "$math_modules" \
      --module-root "$hex_modules" \
      --module-root "$rand_modules" \
	      --module-root "$net_modules" \
	      --module-root "$sockets_modules" \
	      --module-root "$obs_ext_modules" \
	      --module-root "$stdio_modules" \
	      --auto-ffi \
	      >/dev/null
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root tests \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-sandbox/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.1/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-obs/0.1.3/modules" \
      --module-root "$auth_jwt_modules" \
      --module-root "$openssl_modules" \
      --module-root "$crypto_modules" \
      --module-root "$time_modules" \
      --module-root "$fs_modules" \
      --module-root "$db_core_modules" \
      --module-root "$db_sqlite_modules" \
      --module-root "$data_model_modules" \
      --module-root "$json_modules" \
      --module-root "$jsonschema_modules" \
      --module-root "$url_modules" \
      --module-root "$base64_modules" \
      --module-root "$curl_modules" \
      --module-root "$regex_modules" \
      --module-root "$unicode_modules" \
      --module-root "$pb_modules" \
      --module-root "$u64_modules" \
      --module-root "$math_modules" \
      --module-root "$hex_modules" \
      --module-root "$rand_modules" \
      --module-root "$net_modules" \
      --module-root "$sockets_modules" \
      --module-root "$obs_ext_modules" \
      --module-root "$stdio_modules" \
      >/dev/null
  )
else
  echo "skip (requires X07_MCP_LOCAL_DEPS=1)"
fi

step "arch check (x07-mcp)"
x07 arch check --manifest arch/manifest.x07arch.json --lock arch/manifest.lock.json >/dev/null

step "bundle x07-mcp"
mkdir -p dist
x07 bundle --project x07.json --profile os --out dist/x07-mcp >/dev/null
./dist/x07-mcp --help >/dev/null

step "conformance client auth scenarios (phase11 + phase13)"
X07_WORKSPACE_ROOT="$root" ./scripts/ci/materialize_patch_deps.sh conformance/client-x07/x07.json >/dev/null
X07_WORKSPACE_ROOT="$root" x07 pkg lock --project conformance/client-x07/x07.json --check --json=off >/dev/null
X07_WORKSPACE_ROOT="$root" x07 bundle --project conformance/client-x07/x07.json --profile os --out dist/x07-mcp-conformance-client --json=off >/dev/null
./scripts/conformance/run_client_auth_scenario.sh prm-signed-required-missing --client dist/x07-mcp-conformance-client
./scripts/conformance/run_client_auth_scenario.sh prm-multi-as-select-prefer-order

step "scaffold e2e (mcp-server-stdio)"
tmp="$(mktemp -d)"
tmp_dirs+=("$tmp")

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
  x07_root="$(workspace_x07_root)"
  install_project_local_deps_from_workspace "$x07_root" "$PWD"
  x07 pkg lock --project x07.json --offline >/dev/null
else
  x07 pkg lock --project x07.json --check --json=off >/dev/null
fi
x07 arch check --manifest arch/manifest.x07arch.json --lock arch/manifest.lock.json >/dev/null
mkdir -p out
x07 bundle --profile os --out out/mcp-router --json=off >/dev/null
worker_entry_tmp="out/worker_main.entry.x07.json"
jq '.module_id = "main"' src/worker_main.x07.json > "$worker_entry_tmp"
worker_bundle_args=(
  --profile sandbox
  --program "$worker_entry_tmp"
  --out out/mcp-worker
  --json=off
  --sandbox-backend none
  --i-accept-weaker-isolation
  --module-root src
)
while IFS= read -r dep_path; do
  worker_bundle_args+=(--module-root "$dep_path/modules")
done < <(jq -r '.dependencies[].path' x07.json)
x07 bundle "${worker_bundle_args[@]}" >/dev/null
x07 test --manifest tests/tests.json >/dev/null

step "scaffold e2e (mcp-server-http)"
tmp_http="$(mktemp -d)"
tmp_dirs+=("$tmp_http")

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
  auth_jwt_dir="$x07_root/packages/ext/x07-ext-auth-jwt/0.1.4"
  base64_dir="$x07_root/packages/ext/x07-ext-base64-rs/0.1.4"
  crypto_dir="$x07_root/packages/ext/x07-ext-crypto-rs/0.1.4"
  jsonschema_dir="$x07_root/packages/ext/x07-ext-jsonschema-rs/0.1.0"
  fs_dir="$x07_root/packages/ext/x07-ext-fs/0.1.5"
  data_model_dir="$x07_root/packages/ext/x07-ext-data-model/0.1.8"
  db_core_dir="$x07_root/packages/ext/x07-ext-db-core/0.1.9"
  db_sqlite_dir="$x07_root/packages/ext/x07-ext-db-sqlite/0.1.9"
  json_dir="$x07_root/packages/ext/x07-ext-json-rs/0.1.4"
  net_dir="$x07_root/packages/ext/x07-ext-net/0.1.9"
  stdio_dir="$x07_root/packages/ext/x07-ext-stdio/0.1.0"
  csv_dir="$x07_root/packages/ext/x07-ext-csv-rs/0.1.5"
  curl_dir="$x07_root/packages/ext/x07-ext-curl-c/0.1.6"
  hex_dir="$x07_root/packages/ext/x07-ext-hex-rs/0.1.4"
  ini_dir="$x07_root/packages/ext/x07-ext-ini-rs/0.1.4"
  sockets_dir="$x07_root/packages/ext/x07-ext-sockets-c/0.1.6"
  toml_dir="$x07_root/packages/ext/x07-ext-toml-rs/0.1.5"
  unicode_dir="$x07_root/packages/ext/x07-ext-unicode-rs/0.1.5"
  url_dir="$x07_root/packages/ext/x07-ext-url-rs/0.1.4"
  xml_dir="$x07_root/packages/ext/x07-ext-xml-rs/0.1.4"
  yaml_dir="$x07_root/packages/ext/x07-ext-yaml-rs/0.1.4"
  math_dir="$x07_root/packages/ext/x07-ext-math/0.1.4"
  obs_ext_dir="$x07_root/packages/ext/x07-ext-obs/0.1.2"
  openssl_dir="$x07_root/packages/ext/x07-ext-openssl-c/0.1.8"
  pb_dir="$x07_root/packages/ext/x07-ext-pb-rs/0.1.5"
  regex_dir="$x07_root/packages/ext/x07-ext-regex/0.2.4"
  rand_dir="$x07_root/packages/ext/x07-ext-rand/0.1.0"
  time_dir="$x07_root/packages/ext/x07-ext-time-rs/0.1.5"
  u64_dir="$x07_root/packages/ext/x07-ext-u64-rs/0.1.0"

  core_http_dir="$root/packages/ext/x07-ext-mcp-core/0.3.2"
  toolkit_http_dir="$root/packages/ext/x07-ext-mcp-toolkit/0.3.3"
  worker_http_dir="$root/packages/ext/x07-ext-mcp-worker/0.3.3"
  sandbox_http_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.3.3"
  auth_core_http_dir="$root/packages/ext/x07-ext-mcp-auth-core/0.1.1"
  auth_http_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.1"
  obs_http_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.3"
  transport_http_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.3.9"
  rr_http_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.9"
  [[ -d "$auth_jwt_dir" ]] || { echo "ERROR: missing local package: $auth_jwt_dir" >&2; exit 2; }
  [[ -d "$base64_dir" ]] || { echo "ERROR: missing local package: $base64_dir" >&2; exit 2; }
  [[ -d "$crypto_dir" ]] || { echo "ERROR: missing local package: $crypto_dir" >&2; exit 2; }
  [[ -d "$jsonschema_dir" ]] || { echo "ERROR: missing local package: $jsonschema_dir" >&2; exit 2; }
  [[ -d "$fs_dir" ]] || { echo "ERROR: missing local package: $fs_dir" >&2; exit 2; }
  [[ -d "$data_model_dir" ]] || { echo "ERROR: missing local package: $data_model_dir" >&2; exit 2; }
  [[ -d "$db_core_dir" ]] || { echo "ERROR: missing local package: $db_core_dir" >&2; exit 2; }
  [[ -d "$db_sqlite_dir" ]] || { echo "ERROR: missing local package: $db_sqlite_dir" >&2; exit 2; }
  [[ -d "$json_dir" ]] || { echo "ERROR: missing local package: $json_dir" >&2; exit 2; }
  [[ -d "$net_dir" ]] || { echo "ERROR: missing local package: $net_dir" >&2; exit 2; }
  [[ -d "$stdio_dir" ]] || { echo "ERROR: missing local package: $stdio_dir" >&2; exit 2; }
  [[ -d "$csv_dir" ]] || { echo "ERROR: missing local package: $csv_dir" >&2; exit 2; }
  [[ -d "$curl_dir" ]] || { echo "ERROR: missing local package: $curl_dir" >&2; exit 2; }
  [[ -d "$hex_dir" ]] || { echo "ERROR: missing local package: $hex_dir" >&2; exit 2; }
  [[ -d "$ini_dir" ]] || { echo "ERROR: missing local package: $ini_dir" >&2; exit 2; }
  [[ -d "$sockets_dir" ]] || { echo "ERROR: missing local package: $sockets_dir" >&2; exit 2; }
  [[ -d "$toml_dir" ]] || { echo "ERROR: missing local package: $toml_dir" >&2; exit 2; }
  [[ -d "$unicode_dir" ]] || { echo "ERROR: missing local package: $unicode_dir" >&2; exit 2; }
  [[ -d "$url_dir" ]] || { echo "ERROR: missing local package: $url_dir" >&2; exit 2; }
  [[ -d "$xml_dir" ]] || { echo "ERROR: missing local package: $xml_dir" >&2; exit 2; }
  [[ -d "$yaml_dir" ]] || { echo "ERROR: missing local package: $yaml_dir" >&2; exit 2; }
  [[ -d "$regex_dir" ]] || { echo "ERROR: missing local package: $regex_dir" >&2; exit 2; }
  [[ -d "$rand_dir" ]] || { echo "ERROR: missing local package: $rand_dir" >&2; exit 2; }
  [[ -d "$time_dir" ]] || { echo "ERROR: missing local package: $time_dir" >&2; exit 2; }
  [[ -d "$math_dir" ]] || { echo "ERROR: missing local package: $math_dir" >&2; exit 2; }
  [[ -d "$obs_ext_dir" ]] || { echo "ERROR: missing local package: $obs_ext_dir" >&2; exit 2; }
  [[ -d "$openssl_dir" ]] || { echo "ERROR: missing local package: $openssl_dir" >&2; exit 2; }
  [[ -d "$pb_dir" ]] || { echo "ERROR: missing local package: $pb_dir" >&2; exit 2; }
  [[ -d "$u64_dir" ]] || { echo "ERROR: missing local package: $u64_dir" >&2; exit 2; }
  [[ -d "$core_http_dir" ]] || { echo "ERROR: missing local package: $core_http_dir" >&2; exit 2; }
  [[ -d "$toolkit_http_dir" ]] || { echo "ERROR: missing local package: $toolkit_http_dir" >&2; exit 2; }
  [[ -d "$worker_http_dir" ]] || { echo "ERROR: missing local package: $worker_http_dir" >&2; exit 2; }
  [[ -d "$sandbox_http_dir" ]] || { echo "ERROR: missing local package: $sandbox_http_dir" >&2; exit 2; }
  [[ -d "$auth_core_http_dir" ]] || { echo "ERROR: missing local package: $auth_core_http_dir" >&2; exit 2; }
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
    local dst="${4:-$local_deps_dir/$name/$version}"
    x07 pkg remove "$name" >/dev/null 2>&1 || true
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    x07 pkg add "$name@$version" --path "$dst" >/dev/null
  }

  install_local_pkg ext-auth-jwt 0.1.4 "$auth_jwt_dir"
  install_local_pkg ext-base64-rs 0.1.4 "$base64_dir"
  install_local_pkg ext-crypto-rs 0.1.4 "$crypto_dir"
  install_local_pkg ext-jsonschema-rs 0.1.0 "$jsonschema_dir"
  install_local_pkg ext-fs 0.1.5 "$fs_dir"
  install_local_pkg ext-data-model 0.1.8 "$data_model_dir"
  install_local_pkg ext-db-core 0.1.9 "$db_core_dir"
  install_local_pkg ext-db-sqlite 0.1.9 "$db_sqlite_dir"
  install_local_pkg ext-json-rs 0.1.4 "$json_dir"
  install_local_pkg ext-net 0.1.9 "$net_dir"
  install_local_pkg ext-stdio 0.1.0 "$stdio_dir"
  install_local_pkg ext-csv-rs 0.1.5 "$csv_dir"
  install_local_pkg ext-curl-c 0.1.6 "$curl_dir"
  install_local_pkg ext-hex-rs 0.1.4 "$hex_dir"
  install_local_pkg ext-ini-rs 0.1.4 "$ini_dir"
  install_local_pkg ext-sockets-c 0.1.6 "$sockets_dir"
  install_local_pkg ext-toml-rs 0.1.5 "$toml_dir"
  install_local_pkg ext-unicode-rs 0.1.5 "$unicode_dir"
  install_local_pkg ext-url-rs 0.1.4 "$url_dir"
  install_local_pkg ext-xml-rs 0.1.4 "$xml_dir"
  install_local_pkg ext-yaml-rs 0.1.4 "$yaml_dir"
  install_local_pkg ext-regex 0.2.4 "$regex_dir"
  install_local_pkg ext-rand 0.1.0 "$rand_dir"
  install_local_pkg ext-time-rs 0.1.5 "$time_dir"
  install_local_pkg ext-math 0.1.4 "$math_dir"
  install_local_pkg ext-pb-rs 0.1.5 "$pb_dir"
  install_local_pkg ext-u64-rs 0.1.0 "$u64_dir"
  install_local_pkg ext-obs 0.1.2 "$obs_ext_dir"
  install_local_pkg ext-openssl-c 0.1.8 "$openssl_dir"

  install_local_pkg ext-mcp-core 0.3.2 "$core_http_dir"
  install_local_pkg ext-mcp-toolkit 0.3.3 "$toolkit_http_dir"
  install_local_pkg ext-mcp-worker 0.3.3 "$worker_http_dir"
  install_local_pkg ext-mcp-sandbox 0.3.3 "$sandbox_http_dir"
  install_local_pkg ext-mcp-auth-core 0.1.1 "$auth_core_http_dir"
  install_local_pkg ext-mcp-auth 0.4.1 "$auth_http_dir"
  install_local_pkg ext-mcp-obs 0.1.3 "$obs_http_dir"
  install_local_pkg ext-mcp-transport-http 0.3.9 "$transport_http_dir"
  install_local_pkg ext-mcp-rr 0.3.9 "$rr_http_dir"
  tmp_manifest="$(mktemp)"
  tmp_dirs+=("$tmp_manifest")
  jq \
    '.schema_version = "x07.project@0.3.0" |
     .patch = ((.patch // {}) + {"ext-net":{"version":"0.1.9","path":".x07/local/ext-net/0.1.9"}})' \
    x07.json \
    >"$tmp_manifest"
  mv "$tmp_manifest" x07.json
  x07 pkg lock --project x07.json --offline >/dev/null
else
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

  install_local_pkg ext-mcp-core 0.3.2 "$root/packages/ext/x07-ext-mcp-core/0.3.2"
  install_local_pkg ext-mcp-toolkit 0.3.3 "$root/packages/ext/x07-ext-mcp-toolkit/0.3.3"
  install_local_pkg ext-mcp-worker 0.3.3 "$root/packages/ext/x07-ext-mcp-worker/0.3.3"
  install_local_pkg ext-mcp-sandbox 0.3.3 "$root/packages/ext/x07-ext-mcp-sandbox/0.3.3"
  install_local_pkg ext-mcp-auth-core 0.1.1 "$root/packages/ext/x07-ext-mcp-auth-core/0.1.1"
  install_local_pkg ext-mcp-auth 0.4.1 "$root/packages/ext/x07-ext-mcp-auth/0.4.1"
  install_local_pkg ext-mcp-transport-http 0.3.9 "$root/packages/ext/x07-ext-mcp-transport-http/0.3.9"
  install_local_pkg ext-mcp-rr 0.3.9 "$root/packages/ext/x07-ext-mcp-rr/0.3.9"
  install_local_pkg ext-mcp-obs 0.1.3 "$root/packages/ext/x07-ext-mcp-obs/0.1.3"

  x07 pkg lock --project x07.json --json=off >/dev/null
fi
x07 test --manifest tests/tests.json >/dev/null

step "scaffold e2e (mcp-server-http-tasks)"
tmp_tasks="$(mktemp -d)"
tmp_dirs+=("$tmp_tasks")

proj_tasks_rel="proj-http-tasks"
(
  cd "$tmp_tasks"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-http-tasks --dir "$proj_tasks_rel" --machine json >"$tmp_tasks/report.json"
)
proj_tasks="$tmp_tasks/$proj_tasks_rel"
python3 - "$tmp_tasks/report.json" <<'PY'
import json
import sys

path = sys.argv[1]
doc = json.load(open(path, "r", encoding="utf-8"))
if not doc.get("ok"):
    raise SystemExit(f"scaffold report not ok: {doc!r}")
PY

cd "$proj_tasks"

if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  x07_root="$(workspace_x07_root)"
  install_project_local_deps_from_workspace "$x07_root" "$PWD"
  net_override_src="$x07_root/packages/ext/x07-ext-net/0.1.9"
  net_override_dst=".x07/local/ext-net/0.1.9"
  [[ -d "$net_override_src" ]] || { echo "ERROR: missing local package: $net_override_src" >&2; exit 2; }
  rm -rf "$net_override_dst"
  mkdir -p "$(dirname "$net_override_dst")"
  cp -R "$net_override_src" "$net_override_dst"
  tmp_manifest="$(mktemp)"
  tmp_dirs+=("$tmp_manifest")
  jq \
    '.schema_version = "x07.project@0.3.0" |
     .patch = ((.patch // {}) + {"ext-net":{"version":"0.1.9","path":".x07/local/ext-net/0.1.9"}})' \
    x07.json \
    >"$tmp_manifest"
  mv "$tmp_manifest" x07.json
  x07 pkg lock --project x07.json --offline --json=off >/dev/null
else
  x07 pkg lock --project x07.json --check --json=off >/dev/null
fi

x07 test --manifest tests/tests.json >/dev/null

replay_proj=".agent_cache.replay_logging_audit_entry.project.x07.json"
jq \
  '{
    "default_profile": "os",
    "dependencies": .dependencies,
    "entry": "tests/replay_logging_audit_entry.x07.json",
    "lockfile": .lockfile,
    "module_roots": ["src", "tests"],
    "profiles": {
      "os": { "auto_ffi": true, "world": "run-os" }
    },
    "schema_version": .schema_version,
    "world": "run-os"
  }' \
  x07.json \
  >"$replay_proj"
x07 run --project "$replay_proj" --profile os --solve-fuel 2000000000 >/dev/null
	
	echo
	echo "ok: all checks passed"
