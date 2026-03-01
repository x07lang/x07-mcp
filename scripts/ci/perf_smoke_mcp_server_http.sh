#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 2
  fi
}

root="$(repo_root)"
project_dir="${1:-}"
if [[ -z "$project_dir" ]]; then
  echo "Usage: $0 <scaffolded-project-dir>" >&2
  exit 2
fi

require_cmd curl
require_cmd jq
require_cmd python3
require_cmd x07

run_quiet() {
  local log_path="${1:-}"
  shift
  [[ -n "$log_path" ]] || { echo "ERROR: run_quiet missing log path" >&2; return 2; }
  if ! "$@" >"$log_path" 2>&1; then
    echo "ERROR: command failed: $*" >&2
    cat "$log_path" >&2 || true
    return 1
  fi
}

seq_calls="${X07_MCP_PERF_SEQ_CALLS:-200}"
conc_calls="${X07_MCP_PERF_CONC_CALLS:-50}"
# Default tool concurrency lower than the request fanout. Each tool call spawns a
# sandboxed worker and the parent allocates stdout/stderr buffers sized to the tool caps.
# Large `max_tool_conc` values can exhaust the bundle max-memory cap.
default_max_tool_conc="$conc_calls"
if (( default_max_tool_conc > 16 )); then
  default_max_tool_conc=16
fi
max_tool_conc="${X07_MCP_PERF_MAX_TOOL_CONC:-$default_max_tool_conc}"
warm_pool="${X07_MCP_PERF_WARM_POOL_SIZE:-2}"
router_max_mem_bytes="${X07_MCP_PERF_ROUTER_MAX_MEMORY_BYTES:-536870912}"
worker_max_mem_bytes="${X07_MCP_PERF_WORKER_MAX_MEMORY_BYTES:-536870912}"

tmp_dirs=()
cleanup() {
  for d in "${tmp_dirs[@]:-}"; do
    [[ -n "$d" ]] || continue
    rm -rf "$d" || true
  done
}

router_pid=""
kill_router() {
  [[ -n "${router_pid:-}" ]] || return 0
  kill -TERM "$router_pid" >/dev/null 2>&1 || true
  wait "$router_pid" >/dev/null 2>&1 || true
  router_pid=""
}

router_log=""
cfg_path=""
on_exit() {
  local status="$?"
  if [[ "$status" != "0" ]]; then
    echo "ERROR: perf smoke failed (status=$status)" >&2
    if [[ -n "${cfg_path:-}" ]]; then
      local bind=""
      bind="$(jq -r '.transports.http.bind // empty' "$cfg_path" 2>/dev/null || true)"
      echo "cfg_path=$cfg_path bind=$bind" >&2
    fi
    if [[ -n "${router_log:-}" && -f "$router_log" ]]; then
      echo "router log:" >&2
      tail -n 200 "$router_log" >&2 || true
    fi
  fi
  kill_router
  cleanup
  exit "$status"
}
trap on_exit EXIT

project_dir="$(cd "$project_dir" && pwd)"
cd "$project_dir"

mkdir -p out
router_bundle_log="$(mktemp out/mcp-router.bundle.XXXXXX.log)"
tmp_dirs+=("$router_bundle_log")
run_quiet "$router_bundle_log" x07 bundle --profile os --out out/mcp-router --max-memory-bytes "$router_max_mem_bytes" --json=off

worker_entry_tmp="out/worker_main.entry.x07.json"
jq '.module_id = "main"' src/worker_main.x07.json >"$worker_entry_tmp"
worker_bundle_args=(
  --profile sandbox
  --program "$worker_entry_tmp"
  --out out/mcp-worker
  --json=off
  --sandbox-backend none
  --i-accept-weaker-isolation
  --module-root src
)
while IFS= read -r dep_path; do
  worker_bundle_args+=(--module-root "$dep_path/modules")
done < <(jq -r '.dependencies[].path' x07.json)
#
# Bundles produced with `x07 bundle` have a default max-memory cap. This perf smoke uses
# warm worker pools which can allocate multiple per-process stdout/stderr buffers at once;
# set a higher cap so the smoke catches perf regressions rather than failing with OOM.
worker_bundle_log="$(mktemp out/mcp-worker.bundle.XXXXXX.log)"
tmp_dirs+=("$worker_bundle_log")
run_quiet "$worker_bundle_log" x07 bundle "${worker_bundle_args[@]}" --max-memory-bytes "$worker_max_mem_bytes"

port="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

tmp_cfg_dir="$(mktemp -d out/perf-smoke.XXXXXX)"
tmp_dirs+=("$tmp_cfg_dir")
cfg_path="$(mktemp config/mcp.server.perf.json.XXXXXX)"
tmp_dirs+=("$cfg_path")
jq \
  --arg bind "127.0.0.1:${port}" \
  --argjson max_tool_conc "${max_tool_conc}" \
  --argjson warm_pool "${warm_pool}" \
  '.transports.http.bind = $bind |
   .sandbox.router_exec.max_concurrent_per_tool = $max_tool_conc |
   .sandbox.router_exec.warm_pool_size_per_tool = $warm_pool' \
  config/mcp.server.dev.json \
  >"$cfg_path"

url="http://127.0.0.1:${port}/mcp"

router_log="$tmp_cfg_dir/router.log"
X07_MCP_CFG_PATH="$cfg_path" ./out/mcp-router >"$router_log" 2>&1 &
router_pid="$!"

init_body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}'
init_hdr="$tmp_cfg_dir/init.hdr"
init_json="$tmp_cfg_dir/init.json"

sid=""
init_retries="${X07_MCP_PERF_INIT_RETRIES:-400}"
init_sleep_sec="${X07_MCP_PERF_INIT_SLEEP_SECS:-0.1}"
for _ in $(seq 1 "$init_retries"); do
  if ! kill -0 "$router_pid" >/dev/null 2>&1; then
    router_status=0
    wait "$router_pid" >/dev/null 2>&1 || router_status=$?
    bind="$(jq -r '.transports.http.bind // empty' "$cfg_path" 2>/dev/null || true)"
    echo "ERROR: perf smoke router exited early (status=$router_status)" >&2
    echo "cfg_path=$cfg_path bind=$bind" >&2
    echo "router log:" >&2
    tail -n 200 "$router_log" >&2 || true
    exit 2
  fi

  status="$(
    curl -s -D "$init_hdr" -o "$init_json" -w "%{http_code}" \
      -X POST \
      -H 'Origin: http://localhost:3000' \
      -H 'Accept: application/json, text/event-stream' \
      -H 'Content-Type: application/json' \
      -H 'MCP-Protocol-Version: 2025-11-25' \
      --data "$init_body" \
      "$url" 2>/dev/null \
      || true
  )"
  if [[ "$status" == "200" ]]; then
    sid="$(awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' "$init_hdr" | tr -d '\r' | head -n 1)"
    break
  fi
  sleep "$init_sleep_sec"
done
if [[ -z "$sid" ]]; then
  bind="$(jq -r '.transports.http.bind // empty' "$cfg_path" 2>/dev/null || true)"
  echo "ERROR: perf smoke failed to initialize server (url=$url)" >&2
  echo "cfg_path=$cfg_path bind=$bind" >&2
  echo "router log:" >&2
  tail -n 200 "$router_log" >&2 || true
  exit 2
fi

init_notif_status="$(
  curl -sS -o /dev/null -w "%{http_code}" \
    -X POST \
    -H 'Origin: http://localhost:3000' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2025-11-25' \
    -H "MCP-Session-Id: $sid" \
    --data '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
    "$url"
)"
if [[ "$init_notif_status" != "202" ]]; then
  # Some builds return 200 for notifications (no JSON-RPC response body); treat it as ok.
  if [[ "$init_notif_status" != "200" ]]; then
    echo "ERROR: perf smoke initialized notification failed (status=$init_notif_status)" >&2
    exit 2
  fi
fi

for i in $(seq 1 "$seq_calls"); do
  req_id=$((1000 + i))
  tool_body="{\"jsonrpc\":\"2.0\",\"id\":$req_id,\"method\":\"tools/call\",\"params\":{\"name\":\"hello.echo\",\"arguments\":{\"text\":\"hi\"}}}"
  tool_resp_json="$tmp_cfg_dir/tool_call_${req_id}.json"
  status="$(
    curl -sS -o "$tool_resp_json" -w "%{http_code}" \
      -X POST \
      -H 'Origin: http://localhost:3000' \
      -H 'Accept: application/json, text/event-stream' \
      -H 'Content-Type: application/json' \
      -H 'MCP-Protocol-Version: 2025-11-25' \
      -H "MCP-Session-Id: $sid" \
      --data "$tool_body" \
      "$url"
  )"
  if [[ "$status" != "200" ]]; then
    echo "ERROR: perf smoke tools/call failed (i=$i status=$status)" >&2
    cat "$tool_resp_json" >&2 || true
    exit 2
  fi
  tool_is_error="$(jq -r '.result.isError // false' "$tool_resp_json" 2>/dev/null || echo false)"
  rpc_has_error="$(jq -r 'has(\"error\")' "$tool_resp_json" 2>/dev/null || echo false)"
  if [[ "$rpc_has_error" == "true" || "$tool_is_error" == "true" ]]; then
    echo "ERROR: perf smoke tools/call returned error payload (i=$i)" >&2
    cat "$tool_resp_json" >&2 || true
    exit 2
  fi
done

python3 - "$url" "$sid" "$conc_calls" <<'PY'
import concurrent.futures
import http.client
import json
import sys
import urllib.parse

url = sys.argv[1]
sid = sys.argv[2]
conc_calls = int(sys.argv[3])

u = urllib.parse.urlparse(url)
if u.scheme != "http" or not u.hostname or not u.path:
    print(f"ERROR: invalid URL: {url!r}", file=sys.stderr)
    raise SystemExit(2)

host = u.hostname
port = u.port or 80
path = u.path

headers = {
    "Origin": "http://localhost:3000",
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
    "MCP-Protocol-Version": "2025-11-25",
    "MCP-Session-Id": sid,
}

def _call_one(req_id: int) -> int:
    body = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": "tools/call",
        "params": {"name": "hello.echo", "arguments": {"text": "hi"}},
    }
    data = json.dumps(body, separators=(",", ":")).encode("utf-8")
    conn = http.client.HTTPConnection(host, port, timeout=10)
    try:
        conn.request("POST", path, body=data, headers=headers)
        resp = conn.getresponse()
        status = int(getattr(resp, "status", 0) or 0)
        resp.read()
        return status
    except Exception:
        return 0
    finally:
        try:
            conn.close()
        except Exception:
            pass

with concurrent.futures.ThreadPoolExecutor(max_workers=conc_calls) as ex:
    statuses = list(ex.map(_call_one, range(1, conc_calls + 1)))

bad = [s for s in statuses if s != 200]
if bad:
    print(f"ERROR: perf smoke concurrent tools/call failures (bad={len(bad)})", file=sys.stderr)
    print(f"statuses={statuses}", file=sys.stderr)
    raise SystemExit(2)
PY

echo "ok: perf smoke (seq_tools_call=$seq_calls conc_tools_call=$conc_calls)"
