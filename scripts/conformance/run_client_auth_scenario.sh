#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

scenario="${1:-}"
if [[ -z "$scenario" ]]; then
  echo "usage: $0 <scenario> [--client <path>]" >&2
  exit 2
fi
shift

python3 scripts/conformance/run_client_auth_scenario.py --scenario "$scenario" "$@"
