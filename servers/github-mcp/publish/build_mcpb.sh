#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
"${ROOT}/servers/_shared/publish/build_mcpb_common.sh" "github-mcp" "0.1.0"
