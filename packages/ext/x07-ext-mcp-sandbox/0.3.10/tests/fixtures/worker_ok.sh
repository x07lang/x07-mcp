#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _req || true
echo '{"toolResult":{"content":[{"type":"text","text":"ok"}]}}'
