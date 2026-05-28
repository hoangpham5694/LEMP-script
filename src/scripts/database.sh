#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

db_service_name() {
  local svc
  for svc in mysql mariadb mysqld; do
    if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q "^${svc}\.service"; then
      echo "$svc"
      return 0
    fi
    if systemctl status "$svc" >/dev/null 2>&1; then
      echo "$svc"
      return 0
    fi
  done
  echo "mysql"
}

create_database_menu() {
  local db_name create_user yn db_user db_pass user_prefix suffix
  read -r -p "Enter database name: " db_name
  if [[ -z "$db_name" ]]; then
    echo "Database name cannot be empty"; return
  fi
  if ! valid_db_name "$db_name"; then
    echo "Invalid database name."
    echo "Rules: 1-64 chars, start with letter/_ , only letters/numbers/_"
    echo "Disallowed names: mysql, sys, performance_schema, information_schema"
    return
  fi
  db_exec_sql "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  create_user="n"
  read -r -p "Create new user for this database? (y/N): " yn
  yn="${yn:-N}"
  [[ "$yn" =~ ^[Yy]$ ]] && create_user="y"
  if [[ "$create_user" == "y" ]]; then
    user_prefix="${db_name:0:10}"
    suffix="$(random_alnum 4)"
    db_user="${user_prefix}${suffix}"
    db_pass="$(random_alnum 20)"
    db_exec_sql "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    db_exec_sql "ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    db_exec_sql "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';"
    db_exec_sql "FLUSH PRIVILEGES;"
    echo "Database: $db_name"
    echo "Database user: $db_user"
    echo "Database password: $db_pass"
    echo "Host: localhost"
    return
  fi
  echo "Database: $db_name"
}

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
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) systemctl --no-pager -l status "$svc" || true ;;
    2) systemctl start "$svc" ;;
    3) systemctl stop "$svc" ;;
    4) systemctl restart "$svc" ;;
    5) $(db_client_cmd) -uroot -p ;;
    6) create_database_menu ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
