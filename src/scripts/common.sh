#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE_DIR="$(cd -P -- "${SCRIPT_DIR}/.." && pwd -P)"
TEMPLATE_LOCAL_DIR="${BASE_DIR}/templates"
TEMPLATE_SHARED_DIR="/usr/local/share/simple-vps/templates"
ADMINER_ROOT="/var/www/adminer"
ADMINER_FILE="${ADMINER_ROOT}/index.php"
ADMINER_NGINX_CONF="/etc/nginx/conf.d/adminer.conf"
ADMINER_STATE_FILE="/etc/simple-vps/adminer.env"
ADMINER_HTPASSWD="/etc/nginx/.htpasswd-adminer"
ADMINER_SOURCE_NAME="adminer-5.4.2.php"

check_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Please run as root"; exit 1; }
}

detect_primary_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "${ip:-127.0.0.1}"
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

resolve_template_path() {
  local rel="$1"
  if [[ -f "${TEMPLATE_LOCAL_DIR}/${rel}" ]]; then
    echo "${TEMPLATE_LOCAL_DIR}/${rel}"
    return 0
  fi
  if [[ -f "${TEMPLATE_SHARED_DIR}/${rel}" ]]; then
    echo "${TEMPLATE_SHARED_DIR}/${rel}"
    return 0
  fi
  return 1
}

escape_sed_repl() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

render_template_to_file() {
  local template_rel="$1"
  local output_path="$2"
  shift 2
  local template tmp kv key val

  template="$(resolve_template_path "$template_rel" || true)"
  [[ -n "$template" ]] || { echo "Template not found: $template_rel"; return 1; }

  tmp="$(mktemp)"
  cp -f "$template" "$tmp"
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    sed -i.bak "s|{{${key}}}|$(escape_sed_repl "$val")|g" "$tmp"
  done
  rm -f "$tmp.bak"
  install -m 644 "$tmp" "$output_path"
  rm -f "$tmp"
}

reload_nginx() {
  nginx -t
  systemctl reload nginx
}

detect_php_fpm_socket() {
  local sock
  for sock in /run/php/php*-fpm.sock /run/php-fpm/www.sock /var/run/php-fpm/www.sock; do
    if [[ -S "$sock" ]]; then
      echo "$sock"
      return 0
    fi
  done
  return 1
}

sanitize_name() {
  local name="$1"
  printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-'
}

valid_site_name() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  return 0
}

site_conf_path() {
  local site_name="$1"
  echo "/etc/nginx/conf.d/site-$(sanitize_name "$site_name").conf"
}

random_alnum() {
  local len="$1"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}

valid_db_name() {
  local db="$1"
  local lower
  [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || return 1
  (( ${#db} >= 1 && ${#db} <= 64 )) || return 1
  [[ "$db" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  lower="$(printf '%s' "$db" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    mysql|sys|performance_schema|information_schema) return 1 ;;
  esac
  return 0
}

db_client_cmd() {
  if command -v mariadb >/dev/null 2>&1; then
    echo "mariadb"
  else
    echo "mysql"
  fi
}

db_exec_sql() {
  local sql="$1"
  local client
  client="$(db_client_cmd)"
  "$client" -uroot -e "$sql"
}
