#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

open_adminer_port_in_firewall() {
  local port="$1"

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    echo "Opened port ${port}/tcp in firewalld"
  fi

  if command -v ufw >/dev/null 2>&1; then
    if ufw status >/dev/null 2>&1; then
      ufw allow "${port}/tcp" >/dev/null 2>&1 || true
      echo "Opened port ${port}/tcp in UFW"
    fi
  fi
}

load_adminer_state() {
  project_config_load || true
  ADMINER_PORT="${ADMINER_PORT:-}"
  ADMINER_ENABLED="${ADMINER_ENABLED:-on}"
  ADMINER_BASIC_AUTH="${ADMINER_BASIC_AUTH:-on}"
  ADMINER_USERNAME="${ADMINER_USERNAME:-}"
  ADMINER_PASSWORD="${ADMINER_PASSWORD:-}"
}
save_adminer_state() {
  project_config_set_many \
    "ADMINER_PORT" "${ADMINER_PORT}" \
    "ADMINER_ENABLED" "${ADMINER_ENABLED}" \
    "ADMINER_BASIC_AUTH" "${ADMINER_BASIC_AUTH}" \
    "ADMINER_USERNAME" "${ADMINER_USERNAME}" \
    "ADMINER_PASSWORD" "${ADMINER_PASSWORD}"
}
adminer_installed() { [[ -f "$ADMINER_FILE" && -f "$ADMINER_NGINX_CONF" ]]; }
adminer_basic_auth_state() {
  if [[ -f "$ADMINER_NGINX_CONF" ]] && grep -q 'auth_basic_user_file' "$ADMINER_NGINX_CONF" 2>/dev/null; then
    echo "enabled"
  elif [[ -f "$ADMINER_HTPASSWD" || -n "${ADMINER_USERNAME}" && -n "${ADMINER_PASSWORD}" ]]; then
    echo "disabled"
  else
    echo "unset"
  fi
}
resolve_adminer_source() {
  local base src
  base="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/.."
  for src in "${base}/libs/${ADMINER_SOURCE_NAME}" "/usr/local/share/simple-vps/libs/${ADMINER_SOURCE_NAME}"; do
    [[ -f "$src" ]] && { echo "$src"; return 0; }
  done
  return 1
}

adminer_htpasswd_group() {
  if getent group www-data >/dev/null 2>&1; then
    echo "www-data"
  elif getent group nginx >/dev/null 2>&1; then
    echo "nginx"
  else
    echo ""
  fi
}

write_adminer_htpasswd() {
  local user="$1" password="$2" group hash

  group="$(adminer_htpasswd_group)"
  [[ -n "$group" ]] || { echo "Cannot determine nginx group for Adminer auth file"; return 1; }

  hash="$(openssl passwd -apr1 "$password")"
  printf '%s:%s\n' "$user" "$hash" > "$ADMINER_HTPASSWD"
  chown root:"$group" "$ADMINER_HTPASSWD"
  chmod 640 "$ADMINER_HTPASSWD"
}

write_adminer_conf() {
  local port="$1" php_sock="$2" access_line auth_basic_line auth_file_line
  [[ "${ADMINER_ENABLED}" == "off" ]] && access_line="deny all;" || access_line="allow all;"
  if [[ "${ADMINER_BASIC_AUTH}" == "on" && -f "$ADMINER_HTPASSWD" ]]; then
    auth_basic_line="    auth_basic \"Adminer Protected\";"
    auth_file_line="    auth_basic_user_file ${ADMINER_HTPASSWD};"
  else
    auth_basic_line=""
    auth_file_line=""
  fi
  render_template_to_file "nginx/adminer.conf.tpl" "$ADMINER_NGINX_CONF" \
    "PORT=${port}" "ADMINER_ROOT=${ADMINER_ROOT}" "ACCESS_LINE=${access_line}" \
    "PHP_SOCK=${php_sock}" "AUTH_BASIC_LINE=${auth_basic_line}" "AUTH_FILE_LINE=${auth_file_line}" || {
      echo "Failed to render Adminer nginx config template"
      return 1
    }
}
show_adminer_access() {
  load_adminer_state
  if adminer_installed && [[ -n "${ADMINER_PORT}" ]]; then
    echo "Adminer URL: http://$(detect_primary_ip):${ADMINER_PORT}"
    echo "Status: ${ADMINER_ENABLED}"
    case "$(adminer_basic_auth_state)" in
      enabled) echo "Basic auth: enabled" ;;
      disabled) echo "Basic auth: disabled" ;;
      *) echo "Basic auth: not set" ;;
    esac
  else
    echo "Adminer is not installed"
  fi
}
install_adminer() {
  local source_file port php_sock random_pass hash
  adminer_installed && { show_adminer_access; return; }
  command -v openssl >/dev/null 2>&1 || { echo "openssl is required"; return; }
  command -v nginx >/dev/null 2>&1 || { echo "nginx is required"; return; }
  source_file="$(resolve_adminer_source || true)"
  [[ -n "$source_file" ]] || { echo "Cannot find libs/${ADMINER_SOURCE_NAME}."; return; }
  while true; do read -r -p "Enter Adminer port: " port; is_valid_port "$port" && break; echo "Invalid port"; done
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  mkdir -p "$ADMINER_ROOT"; cp -f "$source_file" "$ADMINER_FILE"; chmod 644 "$ADMINER_FILE"
  ADMINER_PORT="$port"; ADMINER_ENABLED="on"; ADMINER_BASIC_AUTH="on"; save_adminer_state
  open_adminer_port_in_firewall "$ADMINER_PORT"
  if [[ ! -f "$ADMINER_HTPASSWD" ]]; then
    random_pass="$(openssl rand -base64 20 | tr -d '\n')"
    write_adminer_htpasswd "adminer" "$random_pass"
    ADMINER_USERNAME="adminer"
    ADMINER_PASSWORD="$random_pass"
    save_adminer_state
    echo "Username: adminer"; echo "Password: ${random_pass}"
  fi
  write_adminer_conf "$ADMINER_PORT" "$php_sock" || return
  reload_nginx; show_adminer_access
}
change_adminer_port() {
  local new_port php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  while true; do read -r -p "Enter new Adminer port: " new_port; is_valid_port "$new_port" && break; echo "Invalid port"; done
  load_adminer_state
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  ADMINER_PORT="$new_port"; save_adminer_state; write_adminer_conf "$ADMINER_PORT" "$php_sock"; open_adminer_port_in_firewall "$ADMINER_PORT"; reload_nginx; show_adminer_access
}
set_adminer_password() {
  local user pass php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  load_adminer_state
  if [[ -z "${ADMINER_PORT}" && -f "$ADMINER_NGINX_CONF" ]]; then
    ADMINER_PORT="$(awk '/^[[:space:]]*listen[[:space:]]+[0-9]+;/{gsub(/;/, "", $2); print $2; exit}' "$ADMINER_NGINX_CONF")"
  fi
  [[ -n "${ADMINER_PORT}" ]] || { echo "Cannot determine Adminer port."; return; }
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  read -r -p "Enter username: " user; [[ -n "$user" ]] || { echo "Username cannot be empty"; return; }
  read -r -s -p "Enter password (leave blank to auto-generate): " pass; echo
  [[ -n "$pass" ]] || pass="$(openssl rand -base64 24 | tr -d '\n')"
  write_adminer_htpasswd "$user" "$pass"
  ADMINER_BASIC_AUTH="on"
  ADMINER_USERNAME="$user"
  ADMINER_PASSWORD="$pass"
  save_adminer_state
  write_adminer_conf "$ADMINER_PORT" "$php_sock" || return
  reload_nginx
  echo "Basic auth updated"
  echo "Username: ${ADMINER_USERNAME}"
  echo "Password: ${ADMINER_PASSWORD}"
}
toggle_adminer_access() {
  local php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  load_adminer_state
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  [[ "${ADMINER_ENABLED}" == "on" ]] && ADMINER_ENABLED="off" || ADMINER_ENABLED="on"
  save_adminer_state; write_adminer_conf "$ADMINER_PORT" "$php_sock"; reload_nginx
  echo "Adminer access is now: ${ADMINER_ENABLED}"
}

enable_adminer_basic_auth() {
  local php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  load_adminer_state
  php_sock="$(detect_php_fpm_socket || true)"
  [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }

  if [[ -f "$ADMINER_HTPASSWD" ]]; then
    ADMINER_BASIC_AUTH="on"
    save_adminer_state
    write_adminer_conf "$ADMINER_PORT" "$php_sock" || return
    reload_nginx
    echo "Basic auth enabled"
  elif [[ -n "${ADMINER_USERNAME}" && -n "${ADMINER_PASSWORD}" ]]; then
    write_adminer_htpasswd "$ADMINER_USERNAME" "$ADMINER_PASSWORD"
    ADMINER_BASIC_AUTH="on"
    save_adminer_state
    write_adminer_conf "$ADMINER_PORT" "$php_sock" || return
    reload_nginx
    echo "Basic auth enabled"
  else
    set_adminer_password
  fi
}

toggle_adminer_basic_auth() {
  local state php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  load_adminer_state
  php_sock="$(detect_php_fpm_socket || true)"
  [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  state="$(adminer_basic_auth_state)"

  case "$state" in
    enabled)
      ADMINER_BASIC_AUTH="off"
      save_adminer_state
      write_adminer_conf "$ADMINER_PORT" "$php_sock" || return
      reload_nginx
      echo "Basic auth disabled"
      ;;
    disabled)
      enable_adminer_basic_auth
      ;;
    *)
      set_adminer_password
      ;;
  esac
}

while true; do
  load_adminer_state
  echo; echo "Adminer management"
  if adminer_installed; then
    show_adminer_access
    case "$(adminer_basic_auth_state)" in
      enabled) basic_auth_menu_label="2) Disable basic auth" ;;
      disabled) basic_auth_menu_label="2) Enable basic auth" ;;
      *) basic_auth_menu_label="2) Create basic auth" ;;
    esac
    case "${ADMINER_ENABLED}" in
      on) access_menu_label="3) Disable access" ;;
      off) access_menu_label="3) Enable access" ;;
      *) access_menu_label="3) Toggle access" ;;
    esac
    echo "1) Change Adminer port"; echo "${basic_auth_menu_label}"; echo "${access_menu_label}"; echo "4) Override basic auth"; echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1) change_adminer_port ;;
      2) toggle_adminer_basic_auth ;;
      3)
        if [[ "$(adminer_basic_auth_state)" == "disabled" ]]; then
          enable_adminer_basic_auth
        else
          toggle_adminer_access
        fi
        ;;
      4) set_adminer_password ;;
      0) exit 0 ;;
      *) echo "Invalid" ;;
    esac
  else
    echo "1) Install Adminer"; echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1) install_adminer ;;
      0) exit 0 ;;
      *) echo "Invalid" ;;
    esac
  fi
done
