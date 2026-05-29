#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

list_php_fpm_services() {
  systemctl list-unit-files --type=service 2>/dev/null | awk '/^php([0-9]+\.[0-9]+-fpm|\-fpm)\.service/ {print $1}'
}

detect_primary_php_fpm_service() {
  local svc
  while IFS= read -r svc; do
    svc="${svc%.service}"
    if systemctl status "$svc" >/dev/null 2>&1; then
      echo "$svc"
      return 0
    fi
  done < <(list_php_fpm_services)

  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^php-fpm\.service'; then
    echo "php-fpm"
  elif systemctl list-unit-files --type=service 2>/dev/null | grep -q '^php8\.2-fpm\.service'; then
    echo "php8.2-fpm"
  else
    echo ""
  fi
}

show_php_status() {
  local svc="$1"
  if [[ -z "$svc" ]]; then
    echo "No PHP-FPM service detected"
    return
  fi
  systemctl --no-pager -l status "$svc" || true
}

php_service_action() {
  local action="$1"
  local svc="$2"
  if [[ -z "$svc" ]]; then
    echo "No PHP-FPM service detected"
    return
  fi

  if systemctl "$action" "$svc"; then
    echo "Success: ${action} ${svc}"
  else
    echo "Failed: ${action} ${svc}"
  fi
  show_php_status "$svc"
}

show_php_info() {
  echo "PHP binary:"
  command -v php || true
  php -v 2>/dev/null | head -n2 || true
  echo
  echo "Detected PHP-FPM services:"
  list_php_fpm_services || true
}

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo "unknown"
  fi
}

detect_php_version() {
  php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true
}

detect_php_ini_path() {
  php -i 2>/dev/null | awk -F'=> ' '/Loaded Configuration File/ {print $2}' | xargs
}

list_php_plugins() {
  local pm php_ver
  pm="$(detect_pm)"
  php_ver="$(detect_php_version)"

  echo "Loaded PHP modules:"
  php -m 2>/dev/null | sort || true
  echo

  case "$pm" in
    apt)
      echo "Installed PHP packages:"
      dpkg -l | awk '/^ii/ && $2 ~ /^php/ {print $2}' | sort || true
      ;;
    dnf)
      echo "Installed PHP packages:"
      rpm -qa | grep -E '^php' | sort || true
      ;;
    *)
      echo "Package manager not supported for package listing"
      ;;
  esac

  if [[ -n "$php_ver" ]]; then
    echo
    echo "Detected PHP version: $php_ver"
  fi
}

install_php_plugin() {
  local plugin pm php_ver pkg
  read -r -p "Enter plugin name (example: redis, imagick, mbstring): " plugin
  [[ -n "$plugin" ]] || { echo "Plugin name is required"; return; }

  pm="$(detect_pm)"
  php_ver="$(detect_php_version)"
  [[ -n "$php_ver" ]] || { echo "Cannot detect PHP version"; return; }

  case "$pm" in
    apt)
      pkg="php${php_ver}-${plugin}"
      apt-get update
      if DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; then
        echo "Installed: $pkg"
      elif DEBIAN_FRONTEND=noninteractive apt-get install -y "php-${plugin}"; then
        echo "Installed fallback package: php-${plugin}"
      else
        echo "Failed to install plugin package for: $plugin"
        return
      fi
      ;;
    dnf)
      pkg="php-${plugin}"
      dnf install -y "$pkg"
      echo "Installed: $pkg"
      ;;
    *)
      echo "Unsupported package manager"
      return
      ;;
  esac

  svc="$(detect_primary_php_fpm_service)"
  if [[ -n "$svc" ]]; then
    php_service_action "restart" "$svc"
  else
    echo "PHP-FPM service not detected, skip restart"
  fi
}

edit_php_ini() {
  local ini svc yn
  ini="$(detect_php_ini_path)"
  if [[ -z "$ini" || "$ini" == "(none)" ]]; then
    echo "Cannot detect php.ini path"
    return
  fi
  if [[ ! -f "$ini" ]]; then
    echo "php.ini not found: $ini"
    return
  fi

  echo "Editing php.ini: $ini"
  if command -v nano >/dev/null 2>&1; then
    nano "$ini"
  elif command -v vi >/dev/null 2>&1; then
    vi "$ini"
  else
    echo "No editor found (nano/vi)"
    return
  fi

  svc="$(detect_primary_php_fpm_service)"
  if [[ -z "$svc" ]]; then
    echo "PHP-FPM service not detected, skip restart"
    return
  fi

  read -r -p "Restart PHP-FPM now to apply changes? (Y/n): " yn
  yn="${yn:-Y}"
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    php_service_action "restart" "$svc"
  else
    echo "Skipped restart"
  fi
}

while true; do
  svc="$(detect_primary_php_fpm_service)"
  echo
  echo "PHP management"
  echo "Current PHP-FPM service: ${svc:-not found}"
  echo "1) Show PHP info"
  echo "2) Status"
  echo "3) Start"
  echo "4) Stop"
  echo "5) Restart"
  echo "6) Reload"
  echo "7) Install PHP plugin"
  echo "8) List PHP plugins"
  echo "9) Edit php.ini"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) show_php_info ;;
    2) show_php_status "$svc" ;;
    3) php_service_action "start" "$svc" ;;
    4) php_service_action "stop" "$svc" ;;
    5) php_service_action "restart" "$svc" ;;
    6) php_service_action "reload" "$svc" ;;
    7) install_php_plugin ;;
    8) list_php_plugins ;;
    9) edit_php_ini ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
