#!/usr/bin/env bash
set -euo pipefail

# Block forever if the request line is truncated (EOF before '\n').
if IFS= read -r _req; then
  echo '{"toolResult":{"content":[{"type":"text","text":"ok"}]}}'
else
  tail -f /dev/null
fi

