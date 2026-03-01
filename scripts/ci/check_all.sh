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

run_with_timeout() {
  local timeout_secs="${1:-0}"
  shift

  if ! [[ "$timeout_secs" =~ ^[0-9]+$ ]] || (( timeout_secs <= 0 )); then
    "$@"
    return $?
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_secs" "$@"
    local exit_code="$?"
    if [[ "$exit_code" == "124" ]]; then
      echo "ERROR: command timed out after ${timeout_secs}s: $*" >&2
    fi
    return "$exit_code"
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_secs" "$@"
    local exit_code="$?"
    if [[ "$exit_code" == "124" ]]; then
      echo "ERROR: command timed out after ${timeout_secs}s: $*" >&2
    fi
    return "$exit_code"
  fi

  python3 - "$timeout_secs" "$@" <<'PY'
import subprocess
import sys

timeout_secs = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    completed = subprocess.run(cmd, check=False, timeout=timeout_secs)
except subprocess.TimeoutExpired:
    print(
        f"ERROR: command timed out after {timeout_secs}s: {' '.join(cmd)}",
        file=sys.stderr,
    )
    raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

tmp_dirs=()
cleanup() {
  for d in "${tmp_dirs[@]:-}"; do
    [[ -n "$d" ]] || continue
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

pin_project_toolchain() {
  local project_dir="$1"
  local pinned_toolchain="$root/x07-toolchain.toml"
  [[ -f "$pinned_toolchain" ]] || return 0
  cp "$pinned_toolchain" "$project_dir/x07-toolchain.toml"
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

step "template runtime secrets guard (check)"
./scripts/ci/check_no_template_runtime_secrets.sh >/dev/null

step "security scripts self-test"
./scripts/security/tests/run.sh >/dev/null

step "MCP pins (check)"
./scripts/ci/check_mcp_pins.sh >/dev/null

step "registry fixtures (check)"
./registry/scripts/check_fixtures.sh

step "fmt check (x07AST JSON)"
while IFS= read -r -d '' f; do
  x07 fmt --input "$f" --check --report-json >/dev/null
done < <(
  find cli/src packages/ext templates conformance/client-x07/src conformance/client-x07/tests \
    \( -type d \( -name .x07 -o -name target -o -name dist -o -name .agent_cache \) -prune \) -o \
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
    \( -type d \( -name .x07 -o -name target -o -name dist -o -name .agent_cache \) -prune \) -o \
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
  "packages/app/x07-mcp/0.3.0/modules"
  "packages/app/x07-mcp/0.4.0/modules"
  "packages/ext/x07-ext-mcp-auth-core/0.1.0/modules"
  "packages/ext/x07-ext-mcp-auth-core/0.1.1/modules"
  "packages/ext/x07-ext-mcp-auth-core/0.1.2/modules"
  "packages/ext/x07-ext-mcp-auth/0.2.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.3.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.3.1/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.0/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.1/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.2/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.3/modules"
  "packages/ext/x07-ext-mcp-auth/0.4.4/modules"
  "packages/ext/x07-ext-mcp-core/0.3.2/modules"
  "packages/ext/x07-ext-mcp-core/0.3.3/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.1/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.2/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.3/modules"
  "packages/ext/x07-ext-mcp-obs/0.1.4/modules"
  "packages/ext/x07-ext-mcp-rr/0.2.3/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.2/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.3/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.4/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.5/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.6/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.7/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.8/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.9/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.10/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.11/modules"
  "packages/ext/x07-ext-mcp-rr/0.3.12/modules"
  "packages/ext/x07-ext-mcp-sandbox/0.3.2/modules"
  "packages/ext/x07-ext-mcp-sandbox/0.3.3/modules"
  "packages/ext/x07-ext-mcp-sandbox/0.3.4/modules"
  "packages/ext/x07-ext-mcp-toolkit/0.3.2/modules"
  "packages/ext/x07-ext-mcp-toolkit/0.3.3/modules"
  "packages/ext/x07-ext-mcp-toolkit/0.3.4/modules"
  "packages/ext/x07-ext-mcp-trust/0.1.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.2.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.3.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.4.0/modules"
  "packages/ext/x07-ext-mcp-trust/0.5.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.1.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.3.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.4.0/modules"
  "packages/ext/x07-ext-mcp-trust-os/0.5.0/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.2.1/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.2/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.3/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.4/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.5/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.6/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.7/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.8/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.9/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.10/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.11/modules"
  "packages/ext/x07-ext-mcp-transport-http/0.3.12/modules"
  "packages/ext/x07-ext-mcp-transport-stdio/0.3.2/modules"
  "packages/ext/x07-ext-mcp-transport-stdio/0.3.3/modules"
  "packages/ext/x07-ext-mcp-worker/0.3.2/modules"
  "packages/ext/x07-ext-mcp-worker/0.3.3/modules"
  "packages/ext/x07-ext-mcp-worker/0.3.4/modules"
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
  auth_jwt_modules="$x07_root/packages/ext/x07-ext-auth-jwt/0.1.5/modules"
  base64_modules="$x07_root/packages/ext/x07-ext-base64-rs/0.1.4/modules"
  crypto_modules="$x07_root/packages/ext/x07-ext-crypto-rs/0.1.4/modules"
  curl_modules="$x07_root/packages/ext/x07-ext-curl-c/0.1.6/modules"
  data_model_modules="$x07_root/packages/ext/x07-ext-data-model/0.1.9/modules"
  db_core_modules="$x07_root/packages/ext/x07-ext-db-core/0.1.10/modules"
  db_sqlite_modules="$x07_root/packages/ext/x07-ext-db-sqlite/0.1.10/modules"
  fs_modules="$x07_root/packages/ext/x07-ext-fs/0.1.5/modules"
  hex_modules="$x07_root/packages/ext/x07-ext-hex-rs/0.1.4/modules"
  json_modules="$x07_root/packages/ext/x07-ext-json-rs/0.1.5/modules"
  jsonschema_modules="$x07_root/packages/ext/x07-ext-jsonschema-rs/0.1.0/modules"
  math_modules="$x07_root/packages/ext/x07-ext-math/0.1.4/modules"
  net_modules="$x07_root/packages/ext/x07-ext-net/0.1.9/modules"
  obs_ext_modules="$x07_root/packages/ext/x07-ext-obs/0.1.3/modules"
  openssl_modules="$x07_root/packages/ext/x07-ext-openssl-c/0.1.9/modules"
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
  auth_core_012_dir="$root/packages/ext/x07-ext-mcp-auth-core/0.1.2"
  [[ -d "$auth_core_012_dir" ]] || { echo "ERROR: missing local package: $auth_core_012_dir" >&2; exit 2; }
  (
    cd "$auth_core_012_dir"
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

  step "package tests (ext-mcp-trust@0.4.0)"
  trust_040_dir="$root/packages/ext/x07-ext-mcp-trust/0.4.0"
  [[ -d "$trust_040_dir" ]] || { echo "ERROR: missing local package: $trust_040_dir" >&2; exit 2; }
  (
    cd "$trust_040_dir"
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

  step "package tests (ext-mcp-trust@0.5.0)"
  trust_050_dir="$root/packages/ext/x07-ext-mcp-trust/0.5.0"
  [[ -d "$trust_050_dir" ]] || { echo "ERROR: missing local package: $trust_050_dir" >&2; exit 2; }
  (
    cd "$trust_050_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$base64_modules" \
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

  step "package tests (ext-mcp-trust-os@0.4.0)"
  trust_os_040_dir="$root/packages/ext/x07-ext-mcp-trust-os/0.4.0"
  [[ -d "$trust_os_040_dir" ]] || { echo "ERROR: missing local package: $trust_os_040_dir" >&2; exit 2; }
  (
    cd "$trust_os_040_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_040_dir/modules" \
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

  step "package tests (ext-mcp-trust-os@0.5.0)"
  trust_os_050_dir="$root/packages/ext/x07-ext-mcp-trust-os/0.5.0"
  [[ -d "$trust_os_050_dir" ]] || { echo "ERROR: missing local package: $trust_os_050_dir" >&2; exit 2; }
  (
    cd "$trust_os_050_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_050_dir/modules" \
      --module-root "$net_modules" \
      --module-root "$url_modules" \
      --module-root "$json_modules" \
      --module-root "$data_model_modules" \
      --module-root "$crypto_modules" \
      --module-root "$hex_modules" \
      --module-root "$fs_modules" \
      --module-root "$unicode_modules" \
      --module-root "$curl_modules" \
      --module-root "$base64_modules" \
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

  step "package tests (x07-mcp@0.3.0 publish trust modules)"
  app_pkg_030_dir="$root/packages/app/x07-mcp/0.3.0"
  [[ -d "$app_pkg_030_dir" ]] || { echo "ERROR: missing local package: $app_pkg_030_dir" >&2; exit 2; }
  (
    cd "$app_pkg_030_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_040_dir/modules" \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$unicode_modules" \
      >/dev/null
  )

  step "package tests (x07-mcp@0.4.0 publish trust modules)"
  app_pkg_040_dir="$root/packages/app/x07-mcp/0.4.0"
  [[ -d "$app_pkg_040_dir" ]] || { echo "ERROR: missing local package: $app_pkg_040_dir" >&2; exit 2; }
  (
    cd "$app_pkg_040_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_050_dir/modules" \
      --module-root "$trust_os_050_dir/modules" \
      --module-root "$crypto_modules" \
      --module-root "$data_model_modules" \
      --module-root "$hex_modules" \
      --module-root "$json_modules" \
      --module-root "$url_modules" \
      --module-root "$unicode_modules" \
      --module-root "$fs_modules" \
      --module-root "$net_modules" \
      --module-root "$curl_modules" \
      --module-root "$base64_modules" \
      >/dev/null
  )

  rr_023_dir="$root/packages/ext/x07-ext-mcp-rr/0.2.3"
  rr_033_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.3"
  rr_034_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.4"
  rr_037_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.7"
  rr_038_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.8"
  rr_039_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.9"
  rr_0310_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.10"
  rr_0311_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.11"
  rr_0312_dir="$root/packages/ext/x07-ext-mcp-rr/0.3.12"
  [[ -d "$rr_023_dir" ]] || { echo "ERROR: missing local package: $rr_023_dir" >&2; exit 2; }
  [[ -d "$rr_033_dir" ]] || { echo "ERROR: missing local package: $rr_033_dir" >&2; exit 2; }
  [[ -d "$rr_034_dir" ]] || { echo "ERROR: missing local package: $rr_034_dir" >&2; exit 2; }
  [[ -d "$rr_037_dir" ]] || { echo "ERROR: missing local package: $rr_037_dir" >&2; exit 2; }
  [[ -d "$rr_038_dir" ]] || { echo "ERROR: missing local package: $rr_038_dir" >&2; exit 2; }
  [[ -d "$rr_039_dir" ]] || { echo "ERROR: missing local package: $rr_039_dir" >&2; exit 2; }
  [[ -d "$rr_0310_dir" ]] || { echo "ERROR: missing local package: $rr_0310_dir" >&2; exit 2; }
  [[ -d "$rr_0311_dir" ]] || { echo "ERROR: missing local package: $rr_0311_dir" >&2; exit 2; }
  [[ -d "$rr_0312_dir" ]] || { echo "ERROR: missing local package: $rr_0312_dir" >&2; exit 2; }

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

  (
    cd "$rr_0312_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-transport-http/0.3.12/modules" \
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
  auth_042_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.2"
  auth_043_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.3"
  auth_044_dir="$root/packages/ext/x07-ext-mcp-auth/0.4.4"
  [[ -d "$auth_020_dir" ]] || { echo "ERROR: missing local package: $auth_020_dir" >&2; exit 2; }
  [[ -d "$auth_030_dir" ]] || { echo "ERROR: missing local package: $auth_030_dir" >&2; exit 2; }
  [[ -d "$auth_031_dir" ]] || { echo "ERROR: missing local package: $auth_031_dir" >&2; exit 2; }
  [[ -d "$auth_040_dir" ]] || { echo "ERROR: missing local package: $auth_040_dir" >&2; exit 2; }
  [[ -d "$auth_041_dir" ]] || { echo "ERROR: missing local package: $auth_041_dir" >&2; exit 2; }
  [[ -d "$auth_042_dir" ]] || { echo "ERROR: missing local package: $auth_042_dir" >&2; exit 2; }
  [[ -d "$auth_043_dir" ]] || { echo "ERROR: missing local package: $auth_043_dir" >&2; exit 2; }
  [[ -d "$auth_044_dir" ]] || { echo "ERROR: missing local package: $auth_044_dir" >&2; exit 2; }
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

  (
    cd "$auth_042_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
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

  (
    cd "$auth_043_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
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

  (
    cd "$auth_044_dir"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
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
  obs_014_dir="$root/packages/ext/x07-ext-mcp-obs/0.1.4"
  [[ -d "$obs_014_dir" ]] || { echo "ERROR: missing local package: $obs_014_dir" >&2; exit 2; }
  (
    cd "$obs_014_dir"
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
  sandbox_034_dir="$root/packages/ext/x07-ext-mcp-sandbox/0.3.4"
  [[ -d "$sandbox_034_dir" ]] || { echo "ERROR: missing local package: $sandbox_034_dir" >&2; exit 2; }
  (
    cd "$sandbox_034_dir"
	    x07 test \
	      --manifest tests/tests.json \
	      --module-root modules \
	      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
	      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
	      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.4/modules" \
	      --module-root "$data_model_modules" \
	      --module-root "$json_modules" \
	      --module-root "$stdio_modules" \
	      --module-root "$unicode_modules" \
	      --module-root "$fs_modules" \
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
          --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.4/modules" \
          --module-root "$data_model_modules" \
          --module-root "$json_modules" \
          --module-root "$stdio_modules" \
          --module-root "$unicode_modules" \
          --module-root "$fs_modules" \
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

    spawn_caps_smoke_json="$(
      (
        cd tests
        x07-os-runner \
          --program router_exec_spawn_caps_entry.x07.json \
          --world run-os \
          --module-root ../modules \
          --module-root . \
          --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
          --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.4/modules" \
          --module-root "$data_model_modules" \
          --module-root "$json_modules" \
          --module-root "$stdio_modules" \
          --module-root "$unicode_modules" \
          --module-root "$fs_modules" \
          --auto-ffi
      )
    )"
    spawn_caps_smoke_ok="$(printf '%s' "$spawn_caps_smoke_json" | jq -r '.solve.ok // false')"
    spawn_caps_smoke_out="$(printf '%s' "$spawn_caps_smoke_json" | jq -r '(.solve.solve_output_b64 // "") | @base64d')"
    if [[ "$spawn_caps_smoke_ok" != "true" || "$spawn_caps_smoke_out" != "ok" ]]; then
      echo "ERROR: ext-mcp-sandbox spawn caps smoke failed (ok=$spawn_caps_smoke_ok out=$spawn_caps_smoke_out)" >&2
      echo "$spawn_caps_smoke_json" >&2
      exit 2
    fi
  )

  step "package tests (ext-mcp-transport-http)"
  transport_http_0312_dir="$root/packages/ext/x07-ext-mcp-transport-http/0.3.12"
  [[ -d "$transport_http_0312_dir" ]] || { echo "ERROR: missing local package: $transport_http_0312_dir" >&2; exit 2; }
  (
    cd "$transport_http_0312_dir"
    # `x07 test --manifest tests/tests.json` runs with CWD=`tests/`, so the socket-level
    # smoke test expects the compiled server solver under `tests/target/...`.
    mkdir -p tests/target/x07test/transport_http_server_smoke
    x07-os-runner \
      --program tests/socket_server_main.x07.json \
      --compiled-out tests/target/x07test/transport_http_server_smoke/socket_server_solver \
      --compile-only \
      --solve-fuel 500000000 \
      --module-root modules \
      --module-root tests \
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-sandbox/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-obs/0.1.4/modules" \
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
      --module-root "$root/packages/ext/x07-ext-mcp-core/0.3.3/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-toolkit/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-sandbox/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-worker/0.3.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth-core/0.1.2/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-auth/0.4.4/modules" \
      --module-root "$root/packages/ext/x07-ext-mcp-obs/0.1.4/modules" \
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
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  tmp_conf="$(mktemp -d)"
  tmp_dirs+=("$tmp_conf")
  cp -R conformance/client-x07 "$tmp_conf/client-x07"
  conf_proj="$tmp_conf/client-x07"

  pin_project_toolchain "$conf_proj"
  x07_root="$(workspace_x07_root)"
  install_project_local_deps_from_workspace "$x07_root" "$conf_proj"
  X07_WORKSPACE_ROOT="$root" ./scripts/ci/materialize_patch_deps.sh "$conf_proj/x07.json" >/dev/null
  (
    cd "$conf_proj"
    x07 pkg lock --project x07.json --offline >/dev/null
  )

  X07_WORKSPACE_ROOT="$root" x07 bundle \
    --project "$conf_proj/x07.json" \
    --profile os \
    --out dist/x07-mcp-conformance-client \
    --json=off \
    >/dev/null
else
  X07_WORKSPACE_ROOT="$root" ./scripts/ci/hydrate_project_deps.sh conformance/client-x07/x07.json >/dev/null
  X07_WORKSPACE_ROOT="$root" x07 bundle \
    --project conformance/client-x07/x07.json \
    --profile os \
    --out dist/x07-mcp-conformance-client \
    --json=off \
    >/dev/null
fi
./scripts/conformance/run_client_auth_scenario.sh prm-signed-required-missing --client dist/x07-mcp-conformance-client
./scripts/conformance/run_client_auth_scenario.sh prm-multi-as-select-prefer-order

step "conformance trust-tlog scenarios"
if [[ "${X07_MCP_LOCAL_DEPS:-0}" == "1" ]]; then
  ./scripts/conformance/run_trust_tlog_scenarios.sh
else
  echo "skip (requires X07_MCP_LOCAL_DEPS=1)"
fi

step "scaffold e2e (mcp-server-stdio)"
tmp="$(mktemp -d)"
tmp_dirs+=("$tmp")
scaffold_test_timeout_secs="${X07_MCP_SCAFFOLD_TEST_TIMEOUT_SECS:-900}"
scaffold_http_test_timeout_secs="${X07_MCP_SCAFFOLD_HTTP_TEST_TIMEOUT_SECS:-1800}"

proj_rel="proj"
(
  cd "$tmp"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-stdio --dir "$proj_rel" --machine json >"$tmp/report.json"
)
proj="$tmp/$proj_rel"
pin_project_toolchain "$proj"
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
  tmp_manifest="$(mktemp)"
  tmp_dirs+=("$tmp_manifest")
  jq \
    '.patch = ((.patch // {}) + {
       "ext-json-rs":{"version":"0.1.5","path":".x07/local/ext-json-rs/0.1.5"}
     })' \
    x07.json \
    >"$tmp_manifest"
  mv "$tmp_manifest" x07.json
  x07 pkg lock --project x07.json --offline >/dev/null
else
  "$root/scripts/ci/materialize_patch_deps.sh" "$PWD/x07.json" >/dev/null
  if ! x07 pkg lock --project x07.json --check --json=off >/dev/null; then
    x07 pkg lock --project x07.json --check --json=off >/dev/null
  fi
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
run_with_timeout "$scaffold_test_timeout_secs" x07 test --manifest tests/tests.json >/dev/null

step "scaffold e2e (mcp-server-http)"
tmp_http="$(mktemp -d)"
tmp_dirs+=("$tmp_http")

proj_http_rel="proj-http"
(
  cd "$tmp_http"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-http --dir "$proj_http_rel" --machine json >"$tmp_http/report.json"
)
proj_http="$tmp_http/$proj_http_rel"
pin_project_toolchain "$proj_http"
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
  x07_root="$(workspace_x07_root)"
  install_project_local_deps_from_workspace "$x07_root" "$PWD"
  tmp_manifest="$(mktemp)"
  tmp_dirs+=("$tmp_manifest")
  jq \
    '.schema_version = "x07.project@0.3.0" |
     .patch = ((.patch // {}) + {
       "ext-json-rs":{"version":"0.1.5","path":".x07/local/ext-json-rs/0.1.5"},
       "ext-net":{"version":"0.1.9","path":".x07/local/ext-net/0.1.9"},
       "ext-u64-rs":{"version":"0.1.4","path":".x07/local/ext-u64-rs/0.1.4"}
     })' \
    x07.json \
    >"$tmp_manifest"
  mv "$tmp_manifest" x07.json
  x07 pkg lock --project x07.json --offline >/dev/null
else
  "$root/scripts/ci/materialize_patch_deps.sh" "$PWD/x07.json" >/dev/null
  if ! x07 pkg lock --project x07.json --check --json=off >/dev/null; then
    x07 pkg lock --project x07.json --check --json=off >/dev/null
  fi
fi
run_with_timeout "$scaffold_http_test_timeout_secs" x07 test --manifest tests/tests.json >/dev/null

step "perf smoke (mcp-server-http)"
if [[ "${X07_MCP_PERF_SMOKE:-0}" == "1" ]]; then
  require_cmd curl
  "$root/scripts/ci/perf_smoke_mcp_server_http.sh" "$proj_http"
else
  echo "skip (set X07_MCP_PERF_SMOKE=1)"
fi

step "scaffold e2e (mcp-server-http-tasks)"
tmp_tasks="$(mktemp -d)"
tmp_dirs+=("$tmp_tasks")

proj_tasks_rel="proj-http-tasks"
(
  cd "$tmp_tasks"
  "$root/dist/x07-mcp" scaffold init --template mcp-server-http-tasks --dir "$proj_tasks_rel" --machine json >"$tmp_tasks/report.json"
)
proj_tasks="$tmp_tasks/$proj_tasks_rel"
pin_project_toolchain "$proj_tasks"
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
  tmp_manifest="$(mktemp)"
  tmp_dirs+=("$tmp_manifest")
  jq \
    '.schema_version = "x07.project@0.3.0" |
     .patch = ((.patch // {}) + {
       "ext-json-rs":{"version":"0.1.5","path":".x07/local/ext-json-rs/0.1.5"},
       "ext-net":{"version":"0.1.9","path":".x07/local/ext-net/0.1.9"},
       "ext-u64-rs":{"version":"0.1.4","path":".x07/local/ext-u64-rs/0.1.4"}
     })' \
    x07.json \
    >"$tmp_manifest"
  mv "$tmp_manifest" x07.json
  x07 pkg lock --project x07.json --offline --json=off >/dev/null
else
  "$root/scripts/ci/materialize_patch_deps.sh" "$PWD/x07.json" >/dev/null
  if ! x07 pkg lock --project x07.json --check --json=off >/dev/null; then
    x07 pkg lock --project x07.json --check --json=off >/dev/null
  fi
fi

run_with_timeout "$scaffold_test_timeout_secs" x07 test --manifest tests/tests.json >/dev/null

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
