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

show_db_status() {
  local svc="$1"
  systemctl --no-pager -l status "$svc" || true
}

db_service_action() {
  local action="$1"
  local svc="$2"
  if systemctl "$action" "$svc"; then
    echo "Success: ${action} ${svc}"
  else
    echo "Failed: ${action} ${svc}"
  fi
  show_db_status "$svc"
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

db_query_with_optional_password() {
  local query="$1"
  local client current_pw
  client="$(db_client_cmd)"

  if "$client" -uroot -e "$query" >/dev/null 2>&1; then
    "$client" -uroot -N -B -e "$query"
    return 0
  fi

  read -r -s -p "Current root password (required): " current_pw
  echo
  if [[ -z "$current_pw" ]]; then
    echo "Current root password is required"
    return 1
  fi

  if "$client" -uroot -p"$current_pw" -e "$query" >/dev/null 2>&1; then
    DB_ROOT_CURRENT_PASSWORD="$current_pw"
    "$client" -uroot -p"$current_pw" -N -B -e "$query"
    return 0
  fi

  echo "Cannot authenticate root user with provided password"
  return 1
}

set_root_password_menu() {
  local client plugin auth has_password="n" yn new_pw confirm_pw escaped_pw
  client="$(db_client_cmd)"

  plugin="$(db_query_with_optional_password "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost' LIMIT 1;" | head -n1 || true)"
  auth="$(db_query_with_optional_password "SELECT authentication_string FROM mysql.user WHERE user='root' AND host='localhost' LIMIT 1;" | head -n1 || true)"

  if [[ -n "$auth" && "$plugin" != "auth_socket" && "$plugin" != "unix_socket" ]]; then
    has_password="y"
  fi

  if [[ "$has_password" == "y" ]]; then
    read -r -p "Root password already exists. Overwrite? (y/N): " yn
    yn="${yn:-N}"
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      echo "Cancelled"
      return
    fi
  fi

  read -r -s -p "New root password: " new_pw
  echo
  [[ -n "$new_pw" ]] || { echo "Password cannot be empty"; return; }
  read -r -s -p "Confirm new root password: " confirm_pw
  echo
  [[ "$new_pw" == "$confirm_pw" ]] || { echo "Password confirmation does not match"; return; }

  escaped_pw="$(sql_escape "$new_pw")"

  if [[ -n "${DB_ROOT_CURRENT_PASSWORD:-}" ]]; then
    "$client" -uroot -p"${DB_ROOT_CURRENT_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -p"${DB_ROOT_CURRENT_PASSWORD}" -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -p"${DB_ROOT_CURRENT_PASSWORD}" -e "FLUSH PRIVILEGES;"
  else
    "$client" -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -e "FLUSH PRIVILEGES;"
  fi

  echo "Root password updated successfully"
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
  echo "7) Set root password"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) show_db_status "$svc" ;;
    2) db_service_action "start" "$svc" ;;
    3) db_service_action "stop" "$svc" ;;
    4) db_service_action "restart" "$svc" ;;
    5) $(db_client_cmd) -uroot -p ;;
    6) create_database_menu ;;
    7) set_root_password_menu ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
