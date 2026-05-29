#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -P -- "${SCRIPT_DIR}/.." && pwd -P)"
LOCAL_UPDATE_SCRIPT="${PROJECT_DIR}/builds/update-from-release.sh"
SHARED_UPDATE_SCRIPT="/opt/simple-vps/builds/update-from-release.sh"

run_update() {
  local updater
  if [[ -x "$LOCAL_UPDATE_SCRIPT" ]]; then
    updater="$LOCAL_UPDATE_SCRIPT"
  elif [[ -x "$SHARED_UPDATE_SCRIPT" ]]; then
    updater="$SHARED_UPDATE_SCRIPT"
  else
    echo "Local update script not found:"
    echo "- $LOCAL_UPDATE_SCRIPT"
    echo "- $SHARED_UPDATE_SCRIPT"
    return 1
  fi

  bash "$updater"
}

while true; do
  echo
  echo "Update"
  echo "1) Check and update to latest release"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) run_update ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
