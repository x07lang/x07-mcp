#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

root="$(repo_root)"
cd "$root"

bad=0

while IFS= read -r -d '' f; do
  echo "ERROR: template must not ship runtime auth secret artifact: $f" >&2
  bad=1
done < <(
  find templates -type f \
    \( -path '*/config/auth/*.secret.b64' -o -path '*/config/auth/*.jwk.json' -o -path '*/config/auth/*.jkt_sha256.txt' \) \
    ! -path '*/tests/*' \
    -print0
)

if ! ./scripts/security/check_no_private_jwk.sh templates servers packages publish conformance >/dev/null; then
  bad=1
fi
if ! ./scripts/security/check_no_secret_b64.sh templates servers packages publish conformance >/dev/null; then
  bad=1
fi

if [[ "$bad" -ne 0 ]]; then
  exit 2
fi

echo "ok: no template runtime secrets/private JWK material detected"
