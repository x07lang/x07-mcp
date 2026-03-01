#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

root="$(repo_root)"
cd "$root"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp" || true
}
trap cleanup EXIT

mkdir -p "$tmp/templates/ok/tests/config/auth"
mkdir -p "$tmp/templates/bad/config/auth"

cp scripts/security/tests/fixtures/should_fail_private.jwk.json "$tmp/templates/ok/tests/config/auth/private.jwk.json"
cp scripts/security/tests/fixtures/should_fail.secret.b64 "$tmp/templates/ok/tests/config/auth/ok.secret.b64"

cp scripts/security/tests/fixtures/should_fail_private.jwk.json "$tmp/templates/bad/config/auth/bad.jwk.json"
cp scripts/security/tests/fixtures/should_fail.secret.b64 "$tmp/templates/bad/config/auth/bad.secret.b64"

if X07_MCP_SECURITY_ROOT="$tmp" scripts/security/check_no_private_jwk.sh >/dev/null 2>&1; then
  echo "ERROR: expected check_no_private_jwk.sh to fail" >&2
  exit 1
fi
rm -f "$tmp/templates/bad/config/auth/bad.jwk.json"
X07_MCP_SECURITY_ROOT="$tmp" scripts/security/check_no_private_jwk.sh >/dev/null

if X07_MCP_SECURITY_ROOT="$tmp" scripts/security/check_no_secret_b64.sh >/dev/null 2>&1; then
  echo "ERROR: expected check_no_secret_b64.sh to fail" >&2
  exit 1
fi
rm -f "$tmp/templates/bad/config/auth/bad.secret.b64"
X07_MCP_SECURITY_ROOT="$tmp" scripts/security/check_no_secret_b64.sh >/dev/null

echo "ok: security checks self-test passed"
