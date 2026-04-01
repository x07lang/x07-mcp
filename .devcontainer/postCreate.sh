#!/usr/bin/env bash
set -euo pipefail

echo "==> x07 doctor"
x07 doctor

echo "==> x07up doctor"
if command -v x07up >/dev/null 2>&1; then
  x07up doctor
else
  echo "WARN: x07up not found on PATH" >&2
fi

echo "==> ready"

