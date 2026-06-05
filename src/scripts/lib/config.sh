#!/bin/bash
set -euo pipefail

APP_CONFIG_FILE="${APP_CONFIG_FILE:-/etc/simple-vps/.env}"
APP_CONFIG_LEGACY_ADMINER_FILE="${APP_CONFIG_LEGACY_ADMINER_FILE:-/etc/simple-vps/adminer.env}"

project_config_dir() {
  dirname "$APP_CONFIG_FILE"
}

project_config_ensure_dir() {
  mkdir -p "$(project_config_dir)"
}

project_config_quote() {
  printf '%q' "$1"
}

project_config_load() {
  if [[ -f "$APP_CONFIG_LEGACY_ADMINER_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$APP_CONFIG_LEGACY_ADMINER_FILE"
  fi

  if [[ -f "$APP_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$APP_CONFIG_FILE"
  fi
}

project_config_write_tmp() {
  local tmp
  tmp="$(mktemp)"
  printf '%s' "$tmp"
}

project_config_set() {
  local key="$1"
  local value="$2"
  local tmp line line_key replaced="0"

  project_config_ensure_dir
  tmp="$(project_config_write_tmp)"

  if [[ -f "$APP_CONFIG_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        ''|'#'*)
          printf '%s\n' "$line" >> "$tmp"
          ;;
        *=*)
          line_key="${line%%=*}"
          if [[ "$line_key" == "$key" ]]; then
            if [[ "$replaced" == "0" ]]; then
              printf '%s=%s\n' "$key" "$(project_config_quote "$value")" >> "$tmp"
              replaced="1"
            fi
          else
            printf '%s\n' "$line" >> "$tmp"
          fi
          ;;
        *)
          printf '%s\n' "$line" >> "$tmp"
          ;;
      esac
    done < "$APP_CONFIG_FILE"
  fi

  if [[ "$replaced" == "0" ]]; then
    printf '%s=%s\n' "$key" "$(project_config_quote "$value")" >> "$tmp"
  fi

  mv -f "$tmp" "$APP_CONFIG_FILE"
  chmod 600 "$APP_CONFIG_FILE"
}

project_config_unset() {
  local key="$1"
  local tmp line line_key

  [[ -f "$APP_CONFIG_FILE" ]] || return 0
  project_config_ensure_dir
  tmp="$(project_config_write_tmp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*)
        printf '%s\n' "$line" >> "$tmp"
        ;;
      *=*)
        line_key="${line%%=*}"
        [[ "$line_key" == "$key" ]] && continue
        printf '%s\n' "$line" >> "$tmp"
        ;;
      *)
        printf '%s\n' "$line" >> "$tmp"
        ;;
    esac
  done < "$APP_CONFIG_FILE"

  mv -f "$tmp" "$APP_CONFIG_FILE"
  chmod 600 "$APP_CONFIG_FILE"
}

project_config_set_many() {
  while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || { echo "project_config_set_many expects key/value pairs"; return 1; }
    project_config_set "$1" "$2"
    shift 2
  done
}

project_config_detect_php_version() {
  php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true
}

project_config_detect_nginx_version() {
  local out
  out="$(nginx -v 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^nginx version: nginx\///p' | head -n1
}

project_config_detect_database_engine() {
  if command -v mariadb >/dev/null 2>&1; then
    echo "mariadb"
  elif command -v mysql >/dev/null 2>&1; then
    echo "mysql"
  elif command -v mysqld >/dev/null 2>&1; then
    echo "mysql"
  else
    echo ""
  fi
}

project_config_detect_database_version() {
  local preferred_engine="${1:-${DB_ENGINE:-}}"
  local out

  case "$preferred_engine" in
    mariadb)
      if command -v mariadb >/dev/null 2>&1; then
        out="$(mariadb --version 2>/dev/null || true)"
      elif command -v mysql >/dev/null 2>&1; then
        out="$(mysql --version 2>/dev/null || true)"
      elif command -v mysqld >/dev/null 2>&1; then
        out="$(mysqld --version 2>/dev/null || true)"
      else
        out=""
      fi
      ;;
    mysql)
      if command -v mysql >/dev/null 2>&1; then
        out="$(mysql --version 2>/dev/null || true)"
      elif command -v mysqld >/dev/null 2>&1; then
        out="$(mysqld --version 2>/dev/null || true)"
      elif command -v mariadb >/dev/null 2>&1; then
        out="$(mariadb --version 2>/dev/null || true)"
      else
        out=""
      fi
      ;;
    *)
      if command -v mariadb >/dev/null 2>&1; then
        out="$(mariadb --version 2>/dev/null || true)"
      elif command -v mysql >/dev/null 2>&1; then
        out="$(mysql --version 2>/dev/null || true)"
      elif command -v mysqld >/dev/null 2>&1; then
        out="$(mysqld --version 2>/dev/null || true)"
      else
        out=""
      fi
      ;;
  esac

  if [[ "$out" == *Distrib* ]]; then
    printf '%s\n' "$out" | awk '{print $5}' | tr -d ','
  else
    printf '%s\n' "$out" | awk '{print $3}'
  fi
}

project_config_refresh_versions() {
  local php_version nginx_version db_engine db_version

  php_version="$(project_config_detect_php_version)"
  nginx_version="$(project_config_detect_nginx_version)"
  db_engine="${DB_ENGINE:-$(project_config_detect_database_engine)}"
  db_version="$(project_config_detect_database_version "$db_engine")"

  [[ -n "$php_version" ]] && project_config_set "PHP_VERSION" "$php_version"
  [[ -n "$nginx_version" ]] && project_config_set "NGINX_VERSION" "$nginx_version"
  [[ -n "$db_engine" ]] && project_config_set "DB_ENGINE" "$db_engine"
  [[ -n "$db_version" ]] && project_config_set_many \
    "DB_VERSION" "$db_version" \
    "MYSQL_VERSION" "$db_version"
}
