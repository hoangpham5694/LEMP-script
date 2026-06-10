#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

COLOR_GREEN=$'\033[32m'
COLOR_RED=$'\033[31m'
COLOR_RESET=$'\033[0m'

show_nginx_status() {
  systemctl --no-pager -l status nginx || true
}

nginx_service_action() {
  local action="$1"
  if systemctl "$action" nginx; then
    echo "Success: ${action} nginx"
  else
    echo "Failed: ${action} nginx"
  fi
  show_nginx_status
}

nginx_toggle_action() {
  if systemctl is-active --quiet nginx; then
    nginx_service_action "stop"
  else
    nginx_service_action "start"
  fi
}

while true; do
  echo
  echo "Nginx management"
  if systemctl is-active --quiet nginx; then
    echo -e "Status: ${COLOR_GREEN}active${COLOR_RESET}"
  else
    echo -e "Status: ${COLOR_RED}inactive${COLOR_RESET}"
  fi
  echo "1) Status"
  if systemctl is-active --quiet nginx; then
    echo "2) Stop"
  else
    echo "2) Start"
  fi
  echo "4) Restart"
  echo "5) Reload"
  echo "6) Test config"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) show_nginx_status ;;
    2) nginx_toggle_action ;;
    4) nginx_service_action "restart" ;;
    5) nginx_service_action "reload" ;;
    6) nginx -t ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
