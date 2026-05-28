#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

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
    1) systemctl --no-pager -l status nginx || true ;;
    2) systemctl start nginx ;;
    3) systemctl stop nginx ;;
    4) systemctl restart nginx ;;
    5) systemctl reload nginx ;;
    6) nginx -t ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
