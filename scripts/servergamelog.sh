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
  export PATH="/app/bin:${PATH}"
  while true; do
    if pid=$(get_instance_pid "$instance"); then
      while ps -p "$pid" > /dev/null 2>&1; do
        log_file=$(ls -1t /app/server/ShooterGame/Saved/Logs/ServerGame.${pid}.*.log 2>/dev/null | head -n 1 || true)
        if [ -f "$log_file" ]; then
          echo "[$instance] Watching log file: $log_file"
          tail -F --pid="$pid" "$log_file" | \
            time_filter.sh | \
            tee >( send_discord.sh )
          break
        fi
        sleep 10 # Wait for new log file to be created.
      done
    fi
    sleep 10 # Wait for new PID to be created.
  done
}

instance="${1:-main}"

source "/app/arkmanager/arkmanager.cfg"
source "/app/arkmanager/instances/${instance}.cfg"
export serverMap

if [ "${arkflag_servergamelog,,}" = "true" ]; then
  echo "Start watching log for instance ${instance} ..."
  watch_log "$instance"
fi
