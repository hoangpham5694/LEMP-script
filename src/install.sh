#!/bin/bash
set -euo pipefail
trap 'echo; echo "[ERROR] Script interrupted"; exit 1' INT TERM

LOG_FILE="/var/log/simple-vps-install.log"
PM_TYPE=""
OS_ID=""
OS_VER=""
PHP_VER=""
DB_ENGINE=""
DB_VER=""
DB_ROOT_PASSWORD=""

_red() { printf '\033[1;31m%b\033[0m' "$1"; }
_green() { printf '\033[1;32m%b\033[0m' "$1"; }
_yellow() { printf '\033[1;33m%b\033[0m' "$1"; }

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts=$(date '+%F %T')
  echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

err() {
  log "ERROR" "$(_red "$*")"
  exit 1
}

run() {
  local cmd="$*"
  log "INFO" "Run: $cmd"
  eval "$cmd" >>"$LOG_FILE" 2>&1 || err "Failed: $cmd"
}

exists() { command -v "$1" >/dev/null 2>&1; }

detect_db_service() {
  local preferred="$1"
  local svc
  local candidates=()

  case "$preferred" in
    mysql) candidates=("mysql" "mariadb" "mysqld") ;;
    mariadb) candidates=("mariadb" "mysql" "mysqld") ;;
    *) candidates=("mysql" "mariadb" "mysqld") ;;
  esac

  for svc in "${candidates[@]}"; do
    if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q "^${svc}\.service"; then
      echo "$svc"
      return 0
    fi
    if systemctl status "${svc}" >/dev/null 2>&1; then
      echo "$svc"
      return 0
    fi
  done

  echo "${candidates[0]}"
}

check_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || err "Please run as root"
}

detect_os() {
  [[ -f /etc/os-release ]] || err "/etc/os-release not found"
  OS_ID=$(awk -F= '/^ID=/{gsub(/"/,"",$2);print $2}' /etc/os-release)
  OS_VER=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2);print $2}' /etc/os-release)

  case "$OS_ID" in
    ubuntu|debian) PM_TYPE="apt" ;;
    centos|rhel|rocky|almalinux|ol|fedora) PM_TYPE="dnf" ;;
    *) err "Unsupported OS: $OS_ID" ;;
  esac
}

prepare_system() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"

  if [[ "$PM_TYPE" == "apt" ]]; then
    run "apt-get update"
    run "DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common"
  else
    run "dnf makecache"
    run "dnf install -y curl ca-certificates dnf-plugins-core"
  fi
}

select_php_version() {
  local choice
  echo "Choose PHP version:"
  echo "1) 8.1"
  echo "2) 8.2"
  echo "3) 8.3"
  echo "4) 8.4"
  while true; do
    read -r -p "Select [1-4] (default: 3): " choice
    choice="${choice:-3}"
    case "$choice" in
      1) PHP_VER="8.1"; return ;;
      2) PHP_VER="8.2"; return ;;
      3) PHP_VER="8.3"; return ;;
      4) PHP_VER="8.4"; return ;;
      *) echo "$(_yellow "Invalid input")" ;;
    esac
  done
}

select_database() {
  local choice
  echo "Choose database engine:"
  echo "1) MariaDB"
  echo "2) MySQL"
  while true; do
    read -r -p "Select [1-2] (default: 1): " choice
    choice="${choice:-1}"
    case "$choice" in
      1)
        DB_ENGINE="mariadb"
        select_mariadb_version
        return
        ;;
      2)
        DB_ENGINE="mysql"
        select_mysql_version
        return
        ;;
      *) echo "$(_yellow "Invalid input")" ;;
    esac
  done
}

read_db_root_password() {
  local pw
  read -r -s -p "Set database root password (leave empty to skip): " pw
  echo
  DB_ROOT_PASSWORD="$pw"
}

select_mariadb_version() {
  local choice
  echo "Choose MariaDB version:"
  echo "1) 10.11"
  echo "2) 11.4"
  echo "3) 11.8"
  while true; do
    read -r -p "Select [1-3] (default: 2): " choice
    choice="${choice:-2}"
    case "$choice" in
      1) DB_VER="10.11"; return ;;
      2) DB_VER="11.4"; return ;;
      3) DB_VER="11.8"; return ;;
      *) echo "$(_yellow "Invalid input")" ;;
    esac
  done
}

select_mysql_version() {
  local choice
  echo "Choose MySQL version:"
  echo "1) 8.0"
  echo "2) 8.4"
  while true; do
    read -r -p "Select [1-2] (default: 2): " choice
    choice="${choice:-2}"
    case "$choice" in
      1) DB_VER="8.0"; return ;;
      2) DB_VER="8.4"; return ;;
      *) echo "$(_yellow "Invalid input")" ;;
    esac
  done
}

install_nginx() {
  if [[ "$PM_TYPE" == "apt" ]]; then
    run "DEBIAN_FRONTEND=noninteractive apt-get install -y nginx"
  else
    run "dnf install -y nginx"
  fi
}

install_php() {
  if [[ "$PM_TYPE" == "apt" ]]; then
    if [[ "$OS_ID" == "ubuntu" ]]; then
      run "add-apt-repository -y ppa:ondrej/php"
    else
      run "curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/deb.sury.org-php.gpg"
      echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi
    run "apt-get update"
    run "DEBIAN_FRONTEND=noninteractive apt-get install -y php${PHP_VER}-fpm php${PHP_VER}-cli php${PHP_VER}-common php${PHP_VER}-mysql php${PHP_VER}-mbstring php${PHP_VER}-xml php${PHP_VER}-curl php${PHP_VER}-zip php${PHP_VER}-gd"
  else
    local major
    major="${OS_VER%%.*}"
    run "dnf install -y https://rpms.remirepo.net/enterprise/remi-release-${major}.rpm"
    run "dnf module reset -y php"
    run "dnf module enable -y php:remi-${PHP_VER}"
    run "dnf install -y php php-cli php-common php-fpm php-mysqlnd php-mbstring php-xml php-curl php-zip php-gd"
  fi
}

install_mariadb() {
  run "curl -fsSL -o /tmp/mariadb_repo_setup.sh https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
  run "chmod +x /tmp/mariadb_repo_setup.sh"
  run "/tmp/mariadb_repo_setup.sh --mariadb-server-version=mariadb-${DB_VER}"

  if [[ "$PM_TYPE" == "apt" ]]; then
    run "apt-get update"
    run "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client"
  else
    run "dnf install -y MariaDB-server MariaDB-client"
  fi
}

install_mysql() {
  if [[ "$PM_TYPE" == "apt" ]]; then
    run "apt-get update"
    if apt-cache show "mysql-server-${DB_VER}" >/dev/null 2>&1; then
      run "DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-${DB_VER} mysql-client-${DB_VER}"
    else
      log "WARN" "mysql-server-${DB_VER} not found in apt repo, using default mysql-server"
      run "DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client"
    fi
  else
    run "dnf module disable -y mysql || true"
    run "dnf install -y https://repo.mysql.com/mysql84-community-release-el${OS_VER%%.*}-1.noarch.rpm"
    if [[ "$DB_VER" == "8.0" ]]; then
      run "dnf config-manager --disable mysql-8.4-lts-community || true"
      run "dnf config-manager --enable mysql80-community || true"
    fi
    run "dnf install -y mysql-community-server mysql-community-client"
  fi
}

set_db_root_password_if_provided() {
  local client escaped_pw current_pw svc

  [[ -n "${DB_ROOT_PASSWORD}" ]] || {
    log "INFO" "Skip setting database root password (empty input)"
    return 0
  }

  client="mysql"
  command -v mariadb >/dev/null 2>&1 && client="mariadb"
  escaped_pw="$(printf "%s" "$DB_ROOT_PASSWORD" | sed "s/'/''/g")"

  if "$client" -uroot -e "SELECT 1;" >/dev/null 2>&1; then
    "$client" -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
    "$client" -uroot -e "FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
    log "INFO" "Database root password has been set"
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -s -p "Current database root password to apply new password: " current_pw
    echo
    if [[ -n "$current_pw" ]] && "$client" -uroot -p"$current_pw" -e "SELECT 1;" >/dev/null 2>&1; then
      "$client" -uroot -p"$current_pw" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
      "$client" -uroot -p"$current_pw" -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_pw}';" >/dev/null 2>&1 || true
      "$client" -uroot -p"$current_pw" -e "FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
      log "INFO" "Database root password has been updated"
      return 0
    fi
  fi

  log "WARN" "Could not set database root password automatically"
}

enable_services() {
  local php_service db_service

  if [[ "$PM_TYPE" == "apt" ]]; then
    php_service="php${PHP_VER}-fpm"
  else
    php_service="php-fpm"
  fi

  db_service="$(detect_db_service "$DB_ENGINE")"

  run "systemctl daemon-reload"
  run "systemctl enable --now nginx"
  run "systemctl enable --now ${php_service}"
  run "systemctl enable --now ${db_service}"
}

create_menu_script() {
  local script_dir
  script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

  [[ -f "${script_dir}/simple-vps.sh" ]] || err "simple-vps.sh not found in ${script_dir}"
  run "install -m 755 ${script_dir}/simple-vps.sh /usr/local/bin/simple-vps"
  run "mkdir -p /usr/local/share/simple-vps/libs"
  run "mkdir -p /usr/local/share/simple-vps/templates"
  run "mkdir -p /usr/local/share/simple-vps/scripts"
  if [[ -f "${script_dir}/libs/adminer-5.4.2.php" ]]; then
    run "install -m 644 ${script_dir}/libs/adminer-5.4.2.php /usr/local/share/simple-vps/libs/adminer-5.4.2.php"
  else
    log "WARN" "Missing ${script_dir}/libs/adminer-5.4.2.php, Adminer install menu may not work"
  fi
  if [[ -d "${script_dir}/templates" ]]; then
    run "cp -a ${script_dir}/templates/. /usr/local/share/simple-vps/templates/"
  else
    log "WARN" "Missing ${script_dir}/templates directory"
  fi
  if [[ -d "${script_dir}/scripts" ]]; then
    run "cp -a ${script_dir}/scripts/. /usr/local/share/simple-vps/scripts/"
    run "chmod +x /usr/local/share/simple-vps/scripts/*.sh"
  else
    log "WARN" "Missing ${script_dir}/scripts directory"
  fi

  if [[ -f "${script_dir}/templates/profile/simple-vps.sh" ]]; then
    run "install -m 644 ${script_dir}/templates/profile/simple-vps.sh /etc/profile.d/simple-vps.sh"
  else
    log "WARN" "Missing ${script_dir}/templates/profile/simple-vps.sh"
  fi
}

show_summary() {
  local php_service db_service
  if [[ "$PM_TYPE" == "apt" ]]; then
    php_service="php${PHP_VER}-fpm"
  else
    php_service="php-fpm"
  fi
  db_service="$(detect_db_service "$DB_ENGINE")"

  echo
  log "INFO" "Install completed"
  log "INFO" "PHP version: $PHP_VER"
  log "INFO" "Database: $DB_ENGINE $DB_VER"
  log "INFO" "Run menu command: simple-vps"
  systemctl --no-pager -l status nginx || true
  systemctl --no-pager -l status "$php_service" || true
  systemctl --no-pager -l status "$db_service" || true
}

main() {
  check_root
  detect_os
  prepare_system

  echo "=== Simple VPS Installer ==="
  echo "OS: $OS_ID $OS_VER"

  select_php_version
  select_database
  read_db_root_password

  log "INFO" "Selected PHP $PHP_VER"
  log "INFO" "Selected DB $DB_ENGINE $DB_VER"

  install_nginx
  install_php

  if [[ "$DB_ENGINE" == "mariadb" ]]; then
    install_mariadb
  else
    install_mysql
  fi

  enable_services
  set_db_root_password_if_provided
  create_menu_script
  show_summary
}

main "$@"
