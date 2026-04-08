#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${ICODEX_BASE_URL:-http://127.0.0.1:8642}"
STATE_DIR="${HOME}/Library/Application Support/iCodex-Connect"
STATE_FILE="${STATE_DIR}/qa_state.json"

usage() {
    cat <<'EOF'
Usage:
  qa_companion.sh health
  qa_companion.sh pair <passcode> [device-name]
  qa_companion.sh verify
  qa_companion.sh devices
  qa_companion.sh controls <thread-id>
  qa_companion.sh preview <thread-id>
  qa_companion.sh press <thread-id> <control-id>
  qa_companion.sh control <thread-id> <action>
  qa_companion.sh recover <thread-id>
  qa_companion.sh afk
  qa_companion.sh expiry
  qa_companion.sh audit [limit]
  qa_companion.sh disconnect
  qa_companion.sh reconnect <passcode> [device-name]
EOF
}

request() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local token=""
    if [[ -f "$STATE_FILE" ]]; then
        token="$(python3 - <<'PY' "$STATE_FILE"
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    print(json.loads(path.read_text()).get("token", ""))
except Exception:
    print("")
PY
)"
    fi

    local args=(-sS -X "$method" "$BASE_URL$path" -H "Content-Type: application/json")
    if [[ -n "$token" ]]; then
        args+=(-H "Authorization: Bearer $token")
    fi
    if [[ -n "$body" ]]; then
        args+=(--data "$body")
    fi
    curl "${args[@]}"
}

save_state() {
    local token="$1"
    local device_id="$2"
    local device_name="$3"
    mkdir -p "$STATE_DIR"
    python3 - <<'PY' "$STATE_FILE" "$token" "$device_id" "$device_name"
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
payload = {
    "token": sys.argv[2],
    "device_id": sys.argv[3],
    "device_name": sys.argv[4],
}
path.write_text(json.dumps(payload, indent=2))
PY
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

cmd="$1"
shift

case "$cmd" in
    health)
        request GET /health
        ;;
    pair)
        passcode="${1:-}"
        device_name="${2:-QA Device}"
        if [[ -z "$passcode" ]]; then
            echo "Missing passcode" >&2
            exit 1
        fi
        response="$(request POST /auth/setup "{\"passcode\":\"$passcode\",\"device_name\":\"$device_name\"}")"
        echo "$response"
        token="$(python3 - <<'PY' "$response"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("api_key", ""))
PY
)"
        device_id="$(python3 - <<'PY' "$response"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("device_id", ""))
PY
)"
        save_state "$token" "$device_id" "$device_name"
        ;;
    reconnect)
        passcode="${1:-}"
        device_name="${2:-QA Device}"
        if [[ -z "$passcode" ]]; then
            echo "Missing passcode" >&2
            exit 1
        fi
        rm -f "$STATE_FILE"
        "$0" pair "$passcode" "$device_name"
        ;;
    verify)
        request GET /auth/verify
        ;;
    devices)
        request GET /devices
        ;;
    controls)
        thread_id="${1:-}"
        if [[ -z "$thread_id" ]]; then
            echo "Missing thread id" >&2
            exit 1
        fi
        request GET "/threads/$thread_id/gui-controls"
        ;;
    preview)
        thread_id="${1:-}"
        if [[ -z "$thread_id" ]]; then
            echo "Missing thread id" >&2
            exit 1
        fi
        request GET "/threads/$thread_id/preview"
        ;;
    press)
        thread_id="${1:-}"
        control_id="${2:-}"
        if [[ -z "$thread_id" || -z "$control_id" ]]; then
            echo "Missing thread id or control id" >&2
            exit 1
        fi
        request POST "/threads/$thread_id/gui-control-press" "{\"control_id\":\"$control_id\"}"
        ;;
    control)
        thread_id="${1:-}"
        action="${2:-}"
        if [[ -z "$thread_id" || -z "$action" ]]; then
            echo "Missing thread id or action" >&2
            exit 1
        fi
        request POST "/threads/$thread_id/control/$action"
        ;;
    recover)
        thread_id="${1:-}"
        if [[ -z "$thread_id" ]]; then
            echo "Missing thread id" >&2
            exit 1
        fi
        request POST "/threads/$thread_id/recover"
        ;;
    afk)
        request GET /qa/afk
        ;;
    expiry)
        request GET /qa/expiry
        ;;
    audit)
        limit="${1:-100}"
        request GET "/audit-log?limit=$limit"
        ;;
    disconnect)
        request POST /auth/disconnect
        rm -f "$STATE_FILE"
        ;;
    *)
        usage
        exit 1
        ;;
esac
