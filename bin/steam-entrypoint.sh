#!/usr/bin/env bash

set -e

[[ -z "${DEBUG}" ]] || [[ "${DEBUG,,}" = "false" ]] || [[ "${DEBUG,,}" = "0" ]] || set -x

if [[ "$(whoami)" != "${STEAM_USER}" ]]; then
  echo "run this script as steam-user"
  exit 1
fi

function may_update() {
  if [[ "${UPDATE_ON_START}" != "true" ]]; then
    return
  fi

  echo "\$UPDATE_ON_START is 'true'..."

  # auto checks if a update is needed, if yes, then update the server or mods
  # (otherwise it just does nothing)
  ${ARKMANAGER} update @main --verbose --update-mods --backup --no-autostart ${BETA_ARGS[@]}
}

function create_missing_dir() {
  for DIRECTORY in ${@}; do
    [[ -n "${DIRECTORY}" ]] || return
    if [[ ! -d "${DIRECTORY}" ]]; then
      mkdir -p "${DIRECTORY}"
      echo "...successfully created ${DIRECTORY}"
    fi
  done
}

function copy_missing_file() {
  SOURCE="${1}"
  DESTINATION="${2}"

  if [[ ! -f "${DESTINATION}" ]]; then
    cp -a "${SOURCE}" "${DESTINATION}"
    echo "...successfully copied ${SOURCE} to ${DESTINATION}"
  fi
}

function needs_install() {
  if [[ ! -d "${ARK_SERVER_VOLUME}/server" ]]; then
    echo "${ARK_SERVER_VOLUME}/server not found ..."
    return 0
  fi

  # Backwards compatibility
  if [[ -f "${ARK_SERVER_VOLUME}/server/version.txt" ]]; then
    echo "${ARK_SERVER_VOLUME}/server/version.txt found."
    return 1
  fi

  if [[ ! -s "${ARK_SERVER_VOLUME}/server/steamapps/appmanifest_376030.acf" ]]; then
    echo "${ARK_SERVER_VOLUME}/server/steamapps/appmanifest_376030.acf not found ..."
    return 0
  fi

  if [[ ! -x "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer" ]]; then
    echo "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer not found ..."
    return 0
  fi
  return 1
}

function add_cluster_cfg() {
  if ! grep -q '^arkopt_ClusterDirOverride='; then
    echo "Remaking cluster settings in arkmanager.cfg ..."
    cat <<EOF >> "${ARK_TOOLS_DIR}/arkmanager.cfg"

# Cluster settings
arkflag_NoTransferFromFiltering=true
arkopt_ClusterDirOverride="/cluster"
arkopt_clusterid=\${CLUSTER_ID:-MyCluster}
EOF
  fi
}

function make_sub_instances_cfg() {
  local key f instance
  local -i i=2
  # remove old sub instance configs
  for f in "${ARK_TOOLS_DIR}/instances/"*.cfg; do
    [[ -f "${f}" ]] || continue
    [[ "$(basename "${f}")" != "main.cfg" ]] || continue
    rm -f "${f}"
  done
  # create new sub instance configs
  for key in ${SUB_INSTANCE_KEYS//,/ }; do
    instance="${key}_INSTANCE_NAME"
    instance="${!instance:-${key}}"
    cat "${TEMPLATE_DIRECTORY}/arkmanager-sub.cfg" | sed -r \
      -e "s/<KEY>/${key}/g" \
      -e "s/<INDEX>/$((i))/g" \
      -e "s/<GAME_CLIENT_PORT>/$((GAME_CLIENT_PORT+i*2))/g" \
      -e "s/<SERVER_LIST_PORT>/$((SERVER_LIST_PORT+i))/g" \
      -e "s/<RCON_PORT>/$((RCON_PORT+i))/g" \
    > "${ARK_TOOLS_DIR}/instances/${instance}.cfg"
    ((i++))
  done
}

function get_all_mod_ids() {
  local -r all_game_mod_ids=(${GAME_MOD_IDS//,/ })
  local key ids
  for key in ${SUB_INSTANCE_KEYS//,/ }; do
    ids="${key}_GAME_MOD_IDS"
    all_game_mod_ids+=("${!ids//,/ }")
  done
  echo "$(echo "${all_game_mod_ids[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
}

args=("$*")
if [[ "${ENABLE_CROSSPLAY}" == "true" ]]; then
  args=('--arkopt,-crossplay' "${args[@]}")
fi
if [[ "${DISABLE_BATTLEYE}" == "true" ]]; then
  args=('--arkopt,-NoBattlEye' "${args[@]}")
fi
BETA_ARGS=(${BETA:+--beta=${BETA}} ${BETA_ACCESSCODE:+--betapassword=${BETA_ACCESSCODE}})

echo "_______________________________________"
echo ""
echo "# Ark Server - $(date)"
echo "# IMAGE_VERSION: '${IMAGE_VERSION}'"
echo "# RUNNING AS USER '${STEAM_USER}' - '$(id -u)'"
echo "# ARGS: ${args[*]}"
if [ -n "${BETA}" ]; then
  echo "# BETA: ${BETA}"
fi
echo "_______________________________________"

ARKMANAGER="$(command -v arkmanager)"
[[ -x "${ARKMANAGER}" ]] || (
  echo "Arkmanger is missing"
  exit 1
)

cd "${ARK_SERVER_VOLUME}"

echo "Setting up folder and file structure..."
create_missing_dir "${ARK_SERVER_VOLUME}/log" "${ARK_SERVER_VOLUME}/backup" "${ARK_SERVER_VOLUME}/staging"

# copy from template to server volume
copy_missing_file "${TEMPLATE_DIRECTORY}/arkmanager.cfg" "${ARK_TOOLS_DIR}/arkmanager.cfg"
copy_missing_file "${TEMPLATE_DIRECTORY}/arkmanager-user.cfg" "${ARK_TOOLS_DIR}/instances/main.cfg"
copy_missing_file "${TEMPLATE_DIRECTORY}/crontab" "${ARK_SERVER_VOLUME}/crontab"

add_cluster_cfg
make_sub_instances_cfg

[[ -L "${ARK_SERVER_VOLUME}/Game.ini" ]] ||
  ln -s ./server/ShooterGame/Saved/Config/LinuxServer/Game.ini Game.ini
[[ -L "${ARK_SERVER_VOLUME}/GameUserSettings.ini" ]] ||
  ln -s ./server/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini GameUserSettings.ini

if needs_install; then
  echo "No game files found. Installing..."

  create_missing_dir \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Saved/SavedArks" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Content/Mods" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux"

  touch "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer"
  chmod +x "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer"

  if ! ${ARKMANAGER} install @main --verbose ${BETA_ARGS[@]}; then
    echo "Installation failed"
    exit 1
  fi
fi

crontab "${ARK_SERVER_VOLUME}/crontab"

declare -a ALL_GAME_MOD_IDS=($(get_all_mod_ids))
if [[ ${#ALL_GAME_MOD_IDS[@]} -gt 0 ]]; then
  echo "Installing mods: '${ALL_GAME_MOD_IDS[*]}' ..."

  for MOD_ID in ${ALL_GAME_MOD_IDS[@]}; do
    echo "...installing '${MOD_ID}'"

    if [[ -d "${ARK_SERVER_VOLUME}/server/ShooterGame/Content/Mods/${MOD_ID}" ]]; then
      echo "...already installed"
      continue
    fi

    ${ARKMANAGER} installmod "${MOD_ID}" --verbose
    echo "...done"
  done
fi

may_update

pids=()
for INSTANCE in ${ARK_SERVER_VOLUME}/arkmanager/instances/*.cfg; do
  if [[ -f "${INSTANCE}" ]]; then
    echo "Run instance ${INSTANCE%.*} ..."
    ${ARKMANAGER} run @$(basename "${INSTANCE%.*}") --verbose ${args[@]} &
    pids+=($!)
  fi
done
wait ${pids[@]}