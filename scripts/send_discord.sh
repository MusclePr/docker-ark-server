#!/usr/bin/env bash
# "${local_time}:${message}" to Discord.

set -o pipefail

WEBHOOK_URL=${DISCORD_WEBHOOK_URL:-}
if [[ -z "${WEBHOOK_URL}" ]]; then
  echo "DISCORD_WEBHOOK_URL environment variable is not set" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command is required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl command is required" >&2
  exit 1
fi

trim() {
  local str="$1"
  str="${str#"${str%%[!$' \t\r\n']*}"}"
  str="${str%"${str##*[!$' \t\r\n']}"}"
  printf '%s' "$str"
}

build_payload() {
  local local_time="$1"
  local message="$2"
  jq -cn --arg name "$local_time" --arg value "$message" '{embeds:[{fields:[{name:$name,value:$value}]}]}'
}

while IFS= read -r raw_line; do
  if [[ "$raw_line" =~ ^([^\]]+\])\ (.+)$ ]]; then
    local_time="${BASH_REMATCH[1]}"
    message=$(trim "${BASH_REMATCH[2]}")
  else
    continue
  fi
  [[ -z "$message" ]] && continue
  [[ "$message" == AdminCmd:* ]] && continue

  short_message="${message:0:1024}"
  payload_json=$(build_payload "$local_time" "$short_message") || continue

  curl -sS -H 'Content-Type: application/json' -X POST -d "$payload_json" "$WEBHOOK_URL" >/dev/null 2>&1 || \
    echo "Failed to post message to Discord" >&2
done
