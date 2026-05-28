#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root: sudo bash cleanup-lemp.sh"
  exit 1
fi

echo "[1/8] Stop services (ignore if not found)..."
for svc in nginx php8.4-fpm php8.3-fpm php8.2-fpm php8.1-fpm php-fpm mysql mariadb mysqld; do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done

echo "[2/8] Purge packages..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get purge -y \
    'nginx*' \
    'php*' \
    'mysql*' \
    'mariadb*' \
    'percona*' || true
  apt-get autoremove -y --purge || true
  apt-get clean || true
elif command -v dnf >/dev/null 2>&1; then
  dnf remove -y \
    'nginx*' \
    'php*' \
    'mysql*' \
    'mariadb*' \
    'percona*' || true
  dnf autoremove -y || true
  dnf clean all || true
else
  echo "Unsupported package manager"
  exit 1
fi

echo "[3/8] Remove configs/logs/data..."
rm -rf \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /etc/php \
  /etc/php-fpm* \
  /var/log/php* \
  /var/lib/php \
  /etc/mysql \
  /etc/my.cnf \
  /etc/my.cnf.d \
  /var/lib/mysql \
  /var/log/mysql* \
  /var/run/mysqld \
  /run/mysqld || true

echo "[4/8] Remove repo files (optional remnants)..."
rm -f \
  /etc/apt/sources.list.d/php.list \
  /etc/apt/sources.list.d/ondrej-ubuntu-php*.list \
  /etc/apt/sources.list.d/mariadb*.list \
  /etc/yum.repos.d/mysql*.repo \
  /etc/yum.repos.d/mariadb*.repo \
  /etc/yum.repos.d/remi*.repo || true

echo "[5/8] Remove system users/groups if exist..."
for u in nginx mysql; do userdel -r "$u" 2>/dev/null || true; done
for g in nginx mysql; do groupdel "$g" 2>/dev/null || true; done

echo "[6/8] Reload systemd..."
systemctl daemon-reload || true
systemctl reset-failed || true

echo "[7/8] Verify..."
echo "Remaining nginx/php/mysql binaries:"
command -v nginx || true
command -v php || true
command -v mysql || true
command -v mariadb || true

echo "[8/8] Done."
echo "System cleaned for re-test."
