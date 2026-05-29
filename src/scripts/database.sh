#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/database-manager.sh"
check_root

while true; do
  svc="$(db_service_name)"
  echo
  echo "Database management ($svc)"
  echo "1) Status"
  echo "2) Start"
  echo "3) Stop"
  echo "4) Restart"
  echo "5) Login SQL shell (root)"
  echo "6) Create database"
  echo "7) Set root password"
  echo "8) Create user for existing database"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) show_db_status "$svc" ;;
    2) db_service_action "start" "$svc" ;;
    3) db_service_action "stop" "$svc" ;;
    4) db_service_action "restart" "$svc" ;;
    5) $(db_client_cmd) -uroot -p ;;
    6)
      if ! create_database_menu; then
        echo "[DB][FAIL] Create database operation failed"
      fi
      ;;
    7)
      if ! set_root_password_menu; then
        echo "[DB][FAIL] Set root password operation failed"
      fi
      ;;
    8)
      if ! create_user_for_existing_database_menu; then
        echo "[DB][FAIL] Create user for existing database operation failed"
      fi
      ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
