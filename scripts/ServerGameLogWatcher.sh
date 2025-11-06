#!/bin/bash

# --------------------------------------------------
# Use the following variables and functions
# from the parent script.
# --------------------------------------------------
# arkflag_servergamelog
# arkserverroot
# arkserverdir
# notify()
# logprint()
#
# --------------------------------------------------
# Add hooks to be called
# --------------------------------------------------
# callbacks_add onServerStart SGLW_onServerStart
#

# --------------------------------------------------
# internal variables and functions prefix: SGLW_
# --------------------------------------------------

# custom message patterns
declare -A SGLW_messagePatterns=(
  # ['pattern']='<level>message'
  ['(.+) joined this ARK!$']=${notifyMsgJoined:-'<green>\1 が参加しました。'}
  ['(.+) left this ARK!$']=${notifyMsgLeft:-'<red>\1 が退出しました。'}
)

#
# message transformer
#
function SGLW_transform() {
  local msg="$1"
  local level=""
  local pattern value
  for pattern in "${!SGLW_messagePatterns[@]}"; do
    if [[ "${msg}" =~ ${pattern} ]]; then
      local -a matches=("${BASH_REMATCH[@]}")
      value="${SGLW_messagePatterns[${pattern}]}"
      if [[ "${value}" =~ ^\<([^>]+)\>(.*)$ ]]; then
        level="${BASH_REMATCH[1]}"
        msg="${BASH_REMATCH[2]}"
      else
        level=""
        msg="$value"
      fi
      if [ "${#matches[@]}" -gt 1 ]; then
        for ((i=1; i<${#matches[@]}; i++)); do
          msg="${msg//\\${i}/${matches[i]}}"
        done
      fi
      break
    fi
  done
  echo "$msg"
  echo "$level"
}

#
# ServerGame.*.log monitoring function
#
function SGLW_monitoring() {
  local logfile="$1"
  local pid="$2"
  local raw
  while IFS= read -r raw; do
    raw="${raw%$'\r'}"
    [ -z "$raw" ] && continue

    # Example log line:
    # raw="[2025.11.10-10.32.01:223][ 97]2025.11.10_10.32.01: PlayerX joined this ARK!"
    # log_date="2025.11.10-10.32.01"
    # log_msec="223"
    # log_id=" 97"
    # log_msg="2025.11.10_10.32.01: PlayerX joined this ARK!"
    if [[ "$raw" =~ ^\[([^]]*):([0-9]{3})\]\[([^]]*)\](.*)$ ]]; then
      local log_date="${BASH_REMATCH[1]}"
      local log_msec="${BASH_REMATCH[2]}"
      local log_id="${BASH_REMATCH[3]}"
      local log_msg="${BASH_REMATCH[4]}"

      # date="2025.11.10_10.32.01"
      # msg="PlayerX joined this ARK!"
      local date msg
      if [[ "$log_msg" =~ ^([^:]*):[[:space:]]?(.*)$ ]]; then
        date="${BASH_REMATCH[1]}"
        msg="${BASH_REMATCH[2]}"
      else
        date="${log_date/-/_}"
        msg="$log_msg"
      fi

      # local_date="2025/11/10 19:32:01" ... TZ=Asia/Tokyo example (JST=UTC+9)
      local local_date=""
      if [ -n "$date" ]; then
        local utc_date_part="${date%%_*}"
        local utc_time_part="${date#*_}"
        local utc_iso="${utc_date_part//./-} ${utc_time_part//./:}"
        local epoch="$(date -u -d "${utc_iso} UTC" +%s 2>/dev/null)"
        if [ -n "$epoch" ]; then
          local_date="$(date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
        fi
        if [ -z "$local_date" ]; then
          local_date="$utc_iso"
        fi
      fi

      # Prepare notification variables

      # shellcheck disable=SC2034
      local notifyvar_raw="$raw"
      # shellcheck disable=SC2034
      local notifyvar_log_date="$log_date"
      # shellcheck disable=SC2034
      local notifyvar_log_msec="$log_msec"
      # shellcheck disable=SC2034
      local notifyvar_log_id="$log_id"
      # shellcheck disable=SC2034
      local notifyvar_log_msg="$log_msg"
      # shellcheck disable=SC2034
      local notifyvar_date="$date"
      # shellcheck disable=SC2034
      local notifyvar_local_date="$local_date"

      mapfile -t SGLW_transformed < <(SGLW_transform "$msg")
      notify "${SGLW_transformed[@]}"

    fi
  done < <(tail --pid="$pid" -f "$logfile" 2>/dev/null)
}

#
# Launch a background monitor for the ServerGame log belonging to the given PID
#
function SGLW_startMonitor() {
  local enable=${arkflag_servergamelog:-true}
  if [[ "${enable,,}" != "true" ]]; then return; fi

  local pid="$1"
  local start_epoch="$(date -u +%s)"
  local logsdir="${arkserverroot}/${arkserverdir:-ShooterGame}/Saved/Logs"
  mkdir -p "$logsdir"

  (
    local start_date="$(date -u -d "@${start_epoch}" '+%Y.%m.%d_%H.%M.%S' 2>/dev/null)"
    logprint "Waiting for \"${logsdir}/ServerGame.${pid}.*.log\". (since ${start_date} UTC)"
    while kill -0 "$pid" >/dev/null 2>&1; do
      # Find the latest ServerGame log file since start_epoch for a given PID.
      local logfile=""
      local newest_epoch=0
      local candidate
      # shellcheck disable=SC2030
      while IFS= read -r -d '' candidate; do
        [ -e "$candidate" ] || continue
        local stamp="${candidate##*/ServerGame."${pid}".}"
        if [[ "$stamp" =~ ^([0-9]{4})\.([0-9]{2})\.([0-9]{2})_([0-9]{2})\.([0-9]{2})\.([0-9]{2}) ]]; then
          local cand_epoch="$(date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null)"
          if [[ -n "$cand_epoch" ]]; then
            if (( cand_epoch < start_epoch )); then
              continue
            fi
            if (( cand_epoch > newest_epoch )); then
              newest_epoch=$cand_epoch
              logfile="$candidate"
            fi
          fi
        fi
      done < <(find "$logsdir" -maxdepth 1 -type f -name "ServerGame.${pid}.*.log" -print0 2>/dev/null)

      if [ -n "$logfile" ]; then
        logprint "Monitoring ServerGame log: ${logfile}"
        SGLW_monitoring "$logfile" "$pid"
        logprint "Terminated ServerGame log: ${logfile}"
        break
      fi

      sleep 2
    done
  ) &
}

function SGLW_install() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This installation script must be run as root."
    exit 1
  fi
  # Add hook to arkmanager script.
  # before:
  #    serverdowntries=0
  # after:
  #    serverdowntries=0 #
  #    SGLW_startMonitor "${serverpid}"
  #
  sed -re 's/(^    serverdowntries=0)$/\1 #\n    SGLW_startMonitor "${serverpid}"/' \
    -i /usr/local/bin/arkmanager
  # Check installation.
  if ! grep -q 'SGLW_startMonitor "${serverpid}"' /usr/local/bin/arkmanager; then
    echo "Failed to install ServerGameLogWatcher hook."
    exit 1
  fi
  # Install ~/.arkmanager.cfg to source this script.
  local user_config="${STEAM_HOME}/.arkmanager.cfg"
  echo "source ${BASH_SOURCE[0]}" > "${user_config}"
  chown ${STEAM_USER}: "${user_config}"
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 && "$0" = "${BASH_SOURCE[0]}" ]]; then
  if [ "$1" = "--install" ]; then
    SGLW_install
  elif [ "$1" = "--test" ]; then
    echo "testing ..."
    source /usr/local/bin/arkmanager
    instance="main"
    logfile="$2"
    [ ! -f "$logfile" ] && logfile=$(ls -t /app/server/ShooterGame/Saved/Logs/ServerGame.*.log | head -n 1)
    [ ! -f "$logfile" ] && echo "No ServerGame log file found." && exit 1
    echo "logfile: $logfile"
    SGLW_monitoring "$logfile" "$$"
  else
    echo "Usage: $(basename "$0") --install | --test [logfile]"
    exit 1
  fi
fi
