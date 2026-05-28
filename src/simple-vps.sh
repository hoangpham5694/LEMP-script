#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_LOCAL_DIR="${SCRIPT_DIR}/scripts"
SCRIPTS_SHARED_DIR="/usr/local/share/simple-vps/scripts"

check_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Please run as root"; exit 1; }
}

run_module() {
  local name="$1"
  local script

  if [[ -x "${SCRIPTS_LOCAL_DIR}/${name}" ]]; then
    script="${SCRIPTS_LOCAL_DIR}/${name}"
  elif [[ -x "${SCRIPTS_SHARED_DIR}/${name}" ]]; then
    script="${SCRIPTS_SHARED_DIR}/${name}"
  else
    echo "Module not found: ${name}"
    return 1
  fi

  "$script"
}

main_menu() {
  while true; do
    echo
    echo "simple-vps menu"
    echo "1) Manage Nginx"
    echo "2) Manage Database"
    echo "3) Manage Adminer"
    echo "4) Create site"
    echo "5) Firewall"
    echo "6) Cache"
    echo "7) Tools"
    echo "8) Cronjob"
    echo "0) Exit"
    read -r -p "Choose: " ch
    case "$ch" in
      1) run_module "nginx.sh" ;;
      2) run_module "database.sh" ;;
      3) run_module "adminer.sh" ;;
      4) run_module "site.sh" ;;
      5) run_module "firewall.sh" ;;
      6) run_module "cache.sh" ;;
      7) run_module "tools.sh" ;;
      8) run_module "cronjob.sh" ;;
      0) exit 0 ;;
      *) echo "Invalid" ;;
    esac
  done
}

check_root
main_menu
