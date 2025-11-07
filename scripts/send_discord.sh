#!/usr/bin/env bash
# "${local_time}|${message}" to Discord.

set -o pipefail

build_payload() {
  local title="$1"
  local message="$2"
  jq -cn --arg name "$title" --arg value "$message" '{embeds:[{fields:[{name:$name,value:$value}]}]}'
}

# A single map does not need to display the map information.
append_info=$([ -n "${MULTI_MAP}" ] && echo " \`${SERVER_MAP}\`" || echo "")

while IFS= read -r raw_line; do
  if [[ "$raw_line" =~ ^([^|]+)\|(.+)$ ]]; then
    local_time="${BASH_REMATCH[1]}"
    message="${BASH_REMATCH[2]}"
  else
    continue
  fi
  [[ -z "$message" ]] && continue
  [[ "$message" == AdminCmd:* ]] && continue

  title="${local_time}${append_info}"
  short_message="${message:0:1024}"
  payload_json=$(build_payload "$title" "$short_message") || continue

  if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
    curl -sS -H 'Content-Type: application/json' -X POST -d "$payload_json" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || \
      echo "Failed to post message to Discord" >&2
  fi
done
