#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

ensure_adminer_state_dir() { mkdir -p "$(dirname "$ADMINER_STATE_FILE")"; }
load_adminer_state() {
  ADMINER_PORT=""; ADMINER_ENABLED="on"
  [[ -f "$ADMINER_STATE_FILE" ]] && source "$ADMINER_STATE_FILE"
}
save_adminer_state() {
  ensure_adminer_state_dir
  cat > "$ADMINER_STATE_FILE" <<STATE
ADMINER_PORT="${ADMINER_PORT}"
ADMINER_ENABLED="${ADMINER_ENABLED}"
STATE
}
adminer_installed() { [[ -f "$ADMINER_FILE" && -f "$ADMINER_NGINX_CONF" ]]; }
resolve_adminer_source() {
  local base src
  base="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/.."
  for src in "${base}/libs/${ADMINER_SOURCE_NAME}" "/usr/local/share/simple-vps/libs/${ADMINER_SOURCE_NAME}"; do
    [[ -f "$src" ]] && { echo "$src"; return 0; }
  done
  return 1
}
write_adminer_conf() {
  local port="$1" php_sock="$2" access_line
  [[ "${ADMINER_ENABLED}" == "off" ]] && access_line="deny all;" || access_line="allow all;"
  render_template_to_file "nginx/adminer.conf.tpl" "$ADMINER_NGINX_CONF" \
    "PORT=${port}" "ADMINER_ROOT=${ADMINER_ROOT}" "ACCESS_LINE=${access_line}" \
    "PHP_SOCK=${php_sock}" "HTPASSWD_FILE=${ADMINER_HTPASSWD}"
}
show_adminer_access() {
  load_adminer_state
  if adminer_installed && [[ -n "${ADMINER_PORT}" ]]; then
    echo "Adminer URL: http://$(detect_primary_ip):${ADMINER_PORT}"
    echo "Status: ${ADMINER_ENABLED}"
  else
    echo "Adminer is not installed"
  fi
}
install_adminer() {
  local source_file port php_sock random_pass hash
  adminer_installed && { show_adminer_access; return; }
  source_file="$(resolve_adminer_source || true)"
  [[ -n "$source_file" ]] || { echo "Cannot find libs/${ADMINER_SOURCE_NAME}."; return; }
  while true; do read -r -p "Enter Adminer port: " port; is_valid_port "$port" && break; echo "Invalid port"; done
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  mkdir -p "$ADMINER_ROOT"; cp -f "$source_file" "$ADMINER_FILE"; chmod 644 "$ADMINER_FILE"
  ADMINER_PORT="$port"; ADMINER_ENABLED="on"; save_adminer_state
  write_adminer_conf "$ADMINER_PORT" "$php_sock"
  if [[ ! -f "$ADMINER_HTPASSWD" ]]; then
    random_pass="$(openssl rand -base64 20 | tr -d '\n')"; hash="$(openssl passwd -apr1 "$random_pass")"
    printf '%s:%s\n' "adminer" "$hash" > "$ADMINER_HTPASSWD"; chmod 640 "$ADMINER_HTPASSWD"
    echo "Username: adminer"; echo "Password: ${random_pass}"
  fi
  reload_nginx; show_adminer_access
}
change_adminer_port() {
  local new_port php_sock
  adminer_installed || { echo "Adminer is not installed"; return; }
  while true; do read -r -p "Enter new Adminer port: " new_port; is_valid_port "$new_port" && break; echo "Invalid port"; done
  load_adminer_state
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  ADMINER_PORT="$new_port"; save_adminer_state; write_adminer_conf "$ADMINER_PORT" "$php_sock"; reload_nginx; show_adminer_access
}
set_adminer_password() {
  local user pass suggested hash
  adminer_installed || { echo "Adminer is not installed"; return; }
  suggested="$(openssl rand -base64 24 | tr -d '\n')"; echo "Suggested strong password: ${suggested}"
  read -r -p "Enter username: " user; [[ -n "$user" ]] || { echo "Username cannot be empty"; return; }
  read -r -s -p "Enter password: " pass; echo; [[ -n "$pass" ]] || { echo "Password cannot be empty"; return; }
  hash="$(openssl passwd -apr1 "$pass")"; printf '%s:%s\n' "$user" "$hash" > "$ADMINER_HTPASSWD"; chmod 640 "$ADMINER_HTPASSWD"
  reload_nginx; echo "Basic auth updated"
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

while true; do
  load_adminer_state
  echo; echo "Adminer management"
  if adminer_installed; then
    show_adminer_access
    echo "1) Change Adminer port"; echo "2) Set Adminer basic auth"; echo "3) Enable/Disable Adminer access"; echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1) change_adminer_port ;;
      2) set_adminer_password ;;
      3) toggle_adminer_access ;;
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
