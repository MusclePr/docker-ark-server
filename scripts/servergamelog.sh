#!/usr/bin/env bash
set -eo pipefail

get_instance_pid() {
  local -r instance="$1"
  # 'arkmanager getpid @main' output example:
  # Running command 'getpid' for instance 'main'
  # 243
  local -r pid=$(arkmanager getpid "@${instance}" 2>/dev/null | awk 'NR==2' || true)
  if [[ $pid =~ ^[0-9]+$ ]]; then
    echo "$pid"
    return 0
  fi
  return 1
}

watch_log() {
  local instance="$1"
  local pid log_file
  while true; do
    if pid=$(get_instance_pid "$instance"); then
      while ps -p "$pid" > /dev/null 2>&1; do
        # shellcheck disable=SC2012 # Because the file patterns are limited, we simply use ls.
        log_file=$(ls -1t /app/server/ShooterGame/Saved/Logs/ServerGame."${pid}".*.log 2>/dev/null | head -n 1 || true)
        if [ -f "$log_file" ]; then
          echo "[$instance] Watching log file: $log_file"
          tail -F --pid="$pid" "$log_file" | time_filter.sh | tee >( send_discord.sh ) | post_filter.sh
          echo "[$instance] Terminated log file: $log_file"
          break
        fi
        sleep 5 # Wait for new log file to be created.
      done
    fi
    sleep 10 # Wait for new PID to be created.
  done
}

export INSTANCE="${1:-main}"

# shellcheck disable=SC1091 # config file does not need to be checked.
source "/app/arkmanager/arkmanager.cfg"
# shellcheck disable=SC1090 # dynamic config file does not need to be checked
source "/app/arkmanager/instances/${INSTANCE}.cfg"

export SERVER_MAP="${serverMap:-}"
# shellcheck disable=SC2012 # Because the file patterns are limited, we simply use ls.
sub_instances=$(ls -1 /app/arkmanager/instances/sub.*.cfg | wc -l || echo 0)
multimap=$([ "$sub_instances" -gt 0 ] && echo "${SERVER_MAP}" || echo "")
export MULTI_MAP="${multimap}"

if [ "${ENABLE_SERVER_GAME_LOG,,}" = "true" ]; then
  if [ "${ENABLE_SERVER_GAME_LOG}" != "${arkflag_servergamelog:-}" ]; then
    echo 'You need to update "/app/arkmanager/arkmanager.cfg".'
    echo 'Either delete this file and let it be automatically regenerated,'
    echo 'or remove the "arkflag_servergamelog=..." to be automatically added.'
    exit 1
  fi

  echo "Start watching log for instance ${INSTANCE} ..."
  watch_log "$INSTANCE"
fi
