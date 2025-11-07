#!/usr/bin/env bash
# gameserverlog pre-filter: convert UTC timestamps to local time

# trim leading and trailing whitespace
trim() {
  local str="$1"
  str="${str#"${str%%[!$' \t\r\n']*}"}"
  str="${str%"${str##*[!$' \t\r\n']}"}"
  printf '%s' "$str"
}

# convert UTC timestamp to local time
to_local() {
  local utc_stamp="$1"
  local converted
  converted=$(printf '%s' "$utc_stamp" | sed -e 's/_/ /' -e 's/\./-/' -e 's/\./-/' -e 's/\./:/' -e 's/\./:/') || return 1
  date -d "${converted} UTC" '+%Y-%m-%d %H:%M:%S'
}

while IFS= read -r raw_line; do
  [[ -z "${raw_line//[[:space:]]/}" ]] && continue

  if [[ "$raw_line" =~ ^\[[^\]]+\]\[[^\]]+\](.*)$ ]]; then
    payload=$(trim "${BASH_REMATCH[1]}")
  else
    continue
  fi
  [[ -z "$payload" ]] && continue

  if [[ "$payload" =~ ^([0-9]{4}\.[0-9]{2}\.[0-9]{2}_[0-9]{2}\.[0-9]{2}\.[0-9]{2}):[[:space:]]*(.*)$ ]]; then
    utc_stamp="${BASH_REMATCH[1]}"
    message=$(trim "${BASH_REMATCH[2]}")
  else
    continue
  fi
  [[ -z "$message" ]] && continue

  if ! local_time=$(to_local "$utc_stamp"); then
    continue
  fi

  echo "${local_time}|${message}"
done
