#!/bin/bash
set -euo pipefail

# Shared database management helpers for simple-vps scripts.
# Requires: common.sh already sourced by caller.

db_service_name() {
  local svc
  for svc in mysql mariadb mysqld; do
    if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q "^${svc}\\.service"; then
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

db_exec_sql_with_auth() {
  local action="$1"
  local sql="$2"
  local client current_pw err_out
  client="$(db_client_cmd)"

  if [[ -n "${DB_ROOT_CURRENT_PASSWORD:-}" ]]; then
    if err_out="$("$client" -uroot -p"${DB_ROOT_CURRENT_PASSWORD}" -e "$sql" 2>&1)"; then
      return 0
    fi
    echo "Database action failed (${action})"
    echo "Detail: ${err_out}"
    return 1
  fi

  if err_out="$("$client" -uroot -e "$sql" 2>&1)"; then
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -s -p "Current root password (required for ${action}): " current_pw
    echo
    if [[ -z "$current_pw" ]]; then
      echo "Database action failed (${action})"
      echo "Detail: current root password is required"
      return 1
    fi

    if err_out="$("$client" -uroot -p"$current_pw" -e "$sql" 2>&1)"; then
      DB_ROOT_CURRENT_PASSWORD="$current_pw"
      return 0
    fi
  fi

  echo "Database action failed (${action})"
  echo "Detail: ${err_out}"
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
    echo "Database name cannot be empty"
    return
  fi
  if ! valid_db_name "$db_name"; then
    echo "Invalid database name."
    echo "Rules: 1-64 chars, start with letter/_ , only letters/numbers/_"
    echo "Disallowed names: mysql, sys, performance_schema, information_schema"
    return
  fi

  db_exec_sql "CREATE DATABASE IF NOT EXISTS \\`$db_name\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  create_user="n"
  read -r -p "Create new user for this database? (y/N): " yn
  yn="${yn:-N}"
  [[ "$yn" =~ ^[Yy]$ ]] && create_user="y"

  create_database_with_optional_user "$db_name" "$create_user"
  db_user="$DB_CREATED_USER"
  db_pass="$DB_CREATED_PASSWORD"

  echo
  echo "Database created successfully"
  echo "-----------------------------"
  echo "Database: $db_name"
  echo "Database user: $db_user"
  echo "Database password: $db_pass"
  echo "Host: localhost"
  echo "-----------------------------"
}

create_database_with_optional_user() {
  local db_name="$1"
  local create_user="${2:-n}"
  local db_user db_pass user_prefix suffix

  db_exec_sql_with_auth "create database" "CREATE DATABASE IF NOT EXISTS \\`$db_name\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1

  if [[ "$create_user" == "y" ]]; then
    user_prefix="${db_name:0:10}"
    suffix="$(random_alnum 4)"
    db_user="${user_prefix}${suffix}"
    db_pass="$(random_alnum 20)"
    db_exec_sql_with_auth "create user" "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" || return 1
    db_exec_sql_with_auth "alter user password" "ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" || return 1
    db_exec_sql_with_auth "grant privileges" "GRANT ALL PRIVILEGES ON \\`$db_name\\`.* TO '$db_user'@'localhost';" || return 1
    db_exec_sql_with_auth "flush privileges" "FLUSH PRIVILEGES;" || return 1
  else
    db_user="(not created)"
    db_pass="(not created)"
  fi

  DB_CREATED_NAME="$db_name"
  DB_CREATED_USER="$db_user"
  DB_CREATED_PASSWORD="$db_pass"
  DB_CREATED_HOST="localhost"
}
