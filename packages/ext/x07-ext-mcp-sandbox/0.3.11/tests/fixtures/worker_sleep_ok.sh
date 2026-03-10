#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _req || true
sleep 1
echo '{"toolResult":{"content":[{"type":"text","text":"ok"}]}}'
