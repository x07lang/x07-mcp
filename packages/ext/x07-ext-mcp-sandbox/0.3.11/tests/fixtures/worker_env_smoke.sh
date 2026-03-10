#!/usr/bin/env bash
set -euo pipefail

IFS= read -r _req || true

home_present=0
if [[ -n "${HOME:-}" ]]; then
  home_present=1
fi

allow_keys_has_home=0
if [[ "${X07_OS_ENV_ALLOW_KEYS:-}" == *"HOME"* ]]; then
  allow_keys_has_home=1
fi

proc_allow_spawn="${X07_OS_PROC_ALLOW_SPAWN:-}"
proc_allow_exec="${X07_OS_PROC_ALLOW_EXEC:-}"
proc_execs="${X07_OS_PROC_ALLOW_EXECS:-}"
proc_prefixes="${X07_OS_PROC_ALLOW_EXEC_PREFIXES:-}"
proc_env_keys="${X07_OS_PROC_ALLOW_ENV_KEYS:-}"
proc_cwd_roots="${X07_OS_PROC_ALLOW_CWD_ROOTS:-}"
proc_max_runtime_ms="${X07_OS_PROC_MAX_RUNTIME_MS:-}"

printf '{"toolResult":{"content":[{"type":"text","text":"home_present=%s allow_keys_has_home=%s proc_allow_spawn=%s proc_allow_exec=%s proc_execs=%s proc_prefixes=%s proc_env_keys=%s proc_cwd_roots=%s proc_max_runtime_ms=%s"}]}}' \
  "${home_present}" \
  "${allow_keys_has_home}" \
  "${proc_allow_spawn}" \
  "${proc_allow_exec}" \
  "${proc_execs}" \
  "${proc_prefixes}" \
  "${proc_env_keys}" \
  "${proc_cwd_roots}" \
  "${proc_max_runtime_ms}"
