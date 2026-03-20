#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _req || true

# Write enough data to stderr to block if the parent doesn't drain it.
dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null

echo '{"toolResult":{"content":[{"type":"text","text":"ok"}]}}'
