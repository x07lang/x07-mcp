#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$(find "$ROOT/packages/app/x07-mcp" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
X07_ROOT="${X07_ROOT:-$ROOT/../x07}"

if [[ -z "$APP_DIR" || ! -d "$APP_DIR" ]]; then
  echo "ERROR: missing x07-mcp app package directory under $ROOT/packages/app/x07-mcp" >&2
  exit 2
fi

if [[ ! -d "$X07_ROOT" ]]; then
  echo "ERROR: missing x07 checkout for local deps: $X07_ROOT" >&2
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 2
  fi
}

require_cmd x07
require_cmd jq

trust_modules="$ROOT/packages/ext/x07-ext-mcp-trust/0.5.0/modules"
trust_os_modules="$ROOT/packages/ext/x07-ext-mcp-trust-os/0.5.0/modules"
net_modules="$X07_ROOT/packages/ext/x07-ext-net/0.1.9/modules"
url_modules="$X07_ROOT/packages/ext/x07-ext-url-rs/0.1.4/modules"
json_modules="$X07_ROOT/packages/ext/x07-ext-json-rs/0.1.5/modules"
data_model_modules="$X07_ROOT/packages/ext/x07-ext-data-model/0.1.8/modules"
crypto_modules="$X07_ROOT/packages/ext/x07-ext-crypto-rs/0.1.4/modules"
hex_modules="$X07_ROOT/packages/ext/x07-ext-hex-rs/0.1.4/modules"
fs_modules="$X07_ROOT/packages/ext/x07-ext-fs/0.1.5/modules"
unicode_modules="$X07_ROOT/packages/ext/x07-ext-unicode-rs/0.1.5/modules"
curl_modules="$X07_ROOT/packages/ext/x07-ext-curl-c/0.1.6/modules"
base64_modules="$X07_ROOT/packages/ext/x07-ext-base64-rs/0.1.4/modules"

for d in \
  "$APP_DIR" \
  "$trust_modules" \
  "$trust_os_modules" \
  "$net_modules" \
  "$url_modules" \
  "$json_modules" \
  "$data_model_modules" \
  "$crypto_modules" \
  "$hex_modules" \
  "$fs_modules" \
  "$unicode_modules" \
  "$curl_modules" \
  "$base64_modules"; do
  [[ -d "$d" ]] || { echo "ERROR: missing module root: $d" >&2; exit 2; }
done

run_case() {
  local baseline_file="$1"
  local id
  local want_status

  id="$(jq -r '.id' "$baseline_file")"
  want_status="$(jq -r '.status' "$baseline_file")"
  [[ -n "$id" && -n "$want_status" ]] || { echo "ERROR: invalid baseline: $baseline_file" >&2; exit 2; }

  local got_status
  if (
    cd "$APP_DIR"
    x07 test \
      --manifest tests/tests.json \
      --module-root modules \
      --module-root "$trust_modules" \
      --module-root "$trust_os_modules" \
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
      --filter "$id" \
      --exact \
      --json=off \
      >/dev/null
  ); then
    got_status="pass"
  else
    got_status="fail"
  fi

  if [[ "$got_status" != "$want_status" ]]; then
    echo "ERROR: trust-tlog scenario $id: got status=$got_status want=$want_status" >&2
    (
      cd "$APP_DIR"
      x07 test \
        --manifest tests/tests.json \
        --module-root modules \
        --module-root "$trust_modules" \
        --module-root "$trust_os_modules" \
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
        --filter "$id" \
        --exact \
        --json=pretty || true
    ) >&2
    exit 2
  fi

  echo "ok: trust-tlog scenario $id"
}

run_case "$ROOT/conformance/trust-tlog/baselines/ok.json"
run_case "$ROOT/conformance/trust-tlog/baselines/unexpected.json"
run_case "$ROOT/conformance/trust-tlog/baselines/inconsistent.json"

echo "ok: trust-tlog conformance scenarios passed"
