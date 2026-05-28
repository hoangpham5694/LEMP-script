#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

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

while true; do
  echo
  echo "Nginx management"
  echo "1) Status"
  echo "2) Start"
  echo "3) Stop"
  echo "4) Restart"
  echo "5) Reload"
  echo "6) Test config"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) show_nginx_status ;;
    2) nginx_service_action "start" ;;
    3) nginx_service_action "stop" ;;
    4) nginx_service_action "restart" ;;
    5) nginx_service_action "reload" ;;
    6) nginx -t ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
