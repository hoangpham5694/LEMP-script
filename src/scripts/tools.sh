#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

TOOLS_ROOT="/var/www/tools"
TOOLS_NGINX_CONF="/etc/nginx/conf.d/tools.conf"
TOOLS_PORT_DEFAULT="8088"

pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo "unknown"
  fi
}

install_base_utils() {
  case "$(pm)" in
    apt) apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar git ;;
    dnf) dnf install -y curl tar git ;;
    *) echo "Unsupported package manager"; return 1 ;;
  esac
}

ensure_tools_nginx() {
  local php_sock port
  php_sock="$(detect_php_fpm_socket || true)"
  [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return 1; }

  if [[ -f "$TOOLS_NGINX_CONF" ]]; then
    port="$(awk '/listen/{print $2}' "$TOOLS_NGINX_CONF" | head -n1 | tr -d ';')"
    port="${port:-$TOOLS_PORT_DEFAULT}"
  else
    read -r -p "Tools web port (default: ${TOOLS_PORT_DEFAULT}): " port
    port="${port:-$TOOLS_PORT_DEFAULT}"
  fi

  cat > "$TOOLS_NGINX_CONF" <<CONF
server {
    listen ${port};
    server_name _;

    root ${TOOLS_ROOT};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:${php_sock};
    }

    location ~ /\. {
        deny all;
    }
}
CONF

  mkdir -p "$TOOLS_ROOT"
  reload_nginx
  echo "Tools Nginx URL base: http://$(detect_primary_ip):${port}"
}

download_extract() {
  local url="$1" dest="$2" strip="${3:-1}" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmp}/pkg.tar.gz"
  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xzf "${tmp}/pkg.tar.gz" -C "$dest" --strip-components="$strip"
  rm -rf "$tmp"
}

install_phpmemcachedadmin() {
  install_base_utils
  ensure_tools_nginx
  download_extract "https://github.com/elijaa/phpmemcachedadmin/archive/refs/heads/master.tar.gz" "${TOOLS_ROOT}/phpmemcachedadmin" 1
  echo "PHPMemcachedAdmin: http://$(detect_primary_ip):$(awk '/listen/{print $2}' "$TOOLS_NGINX_CONF"|head -n1|tr -d ';')/phpmemcachedadmin"
}

install_phpredisadmin() {
  install_base_utils
  ensure_tools_nginx
  download_extract "https://github.com/erikdubbelboer/phpRedisAdmin/archive/refs/heads/master.tar.gz" "${TOOLS_ROOT}/phpredisadmin" 1
  if [[ -f "${TOOLS_ROOT}/phpredisadmin/includes/config.sample.inc.php" ]]; then
    cp -f "${TOOLS_ROOT}/phpredisadmin/includes/config.sample.inc.php" "${TOOLS_ROOT}/phpredisadmin/includes/config.inc.php"
  fi
  echo "phpRedisAdmin: http://$(detect_primary_ip):$(awk '/listen/{print $2}' "$TOOLS_NGINX_CONF"|head -n1|tr -d ';')/phpredisadmin"
}

install_phpsysinfo() {
  install_base_utils
  ensure_tools_nginx
  download_extract "https://github.com/phpsysinfo/phpsysinfo/archive/refs/heads/master.tar.gz" "${TOOLS_ROOT}/phpsysinfo" 1
  if [[ -f "${TOOLS_ROOT}/phpsysinfo/phpsysinfo.ini.new" && ! -f "${TOOLS_ROOT}/phpsysinfo/phpsysinfo.ini" ]]; then
    cp -f "${TOOLS_ROOT}/phpsysinfo/phpsysinfo.ini.new" "${TOOLS_ROOT}/phpsysinfo/phpsysinfo.ini"
  fi
  echo "phpSysInfo: http://$(detect_primary_ip):$(awk '/listen/{print $2}' "$TOOLS_NGINX_CONF"|head -n1|tr -d ';')/phpsysinfo"
}

install_opcache_dashboard() {
  install_base_utils
  ensure_tools_nginx
  download_extract "https://github.com/amnuts/opcache-gui/archive/refs/heads/master.tar.gz" "${TOOLS_ROOT}/opcache-dashboard" 1
  echo "Opcache Dashboard: http://$(detect_primary_ip):$(awk '/listen/{print $2}' "$TOOLS_NGINX_CONF"|head -n1|tr -d ';')/opcache-dashboard"
}

pureftpd_menu() {
  while true; do
    echo
    echo "Pureftpd"
    echo "1) Install"
    echo "2) Status"
    echo "3) Start"
    echo "4) Stop"
    echo "5) Restart"
    echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1)
        case "$(pm)" in
          apt) apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y pure-ftpd ;;
          dnf) dnf install -y pure-ftpd ;;
          *) echo "Unsupported package manager"; continue ;;
        esac
        if systemctl list-unit-files | grep -q '^pure-ftpd\.service'; then
          systemctl enable --now pure-ftpd
        else
          systemctl enable --now pure-ftpd.service || true
        fi
        ;;
      2)
        if systemctl list-unit-files | grep -q '^pure-ftpd\.service'; then
          systemctl --no-pager -l status pure-ftpd || true
        else
          systemctl --no-pager -l status pure-ftpd.service || true
        fi
        ;;
      3) systemctl start pure-ftpd || systemctl start pure-ftpd.service ;;
      4) systemctl stop pure-ftpd || systemctl stop pure-ftpd.service ;;
      5) systemctl restart pure-ftpd || systemctl restart pure-ftpd.service ;;
      0) return ;;
      *) echo "Invalid" ;;
    esac
  done
}

while true; do
  echo
  echo "Tools"
  echo "1) Pureftpd"
  echo "2) PHPMemcachedAdmin"
  echo "3) phpRedisAdmin"
  echo "4) phpSysInfo"
  echo "5) Opcache Dashboard"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) pureftpd_menu ;;
    2) install_phpmemcachedadmin ;;
    3) install_phpredisadmin ;;
    4) install_phpsysinfo ;;
    5) install_opcache_dashboard ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
