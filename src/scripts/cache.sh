#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo "unknown"
  fi
}

cache_install_memcached() {
  case "$(detect_pm)" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y memcached
      ;;
    dnf)
      dnf install -y memcached
      ;;
    *)
      echo "Unsupported package manager"
      return 1
      ;;
  esac
  systemctl enable --now memcached
  echo "memcached installed and started"
}

cache_install_redis() {
  case "$(detect_pm)" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server
      ;;
    dnf)
      dnf install -y redis
      ;;
    *)
      echo "Unsupported package manager"
      return 1
      ;;
  esac

  if systemctl list-unit-files | grep -q '^redis-server\.service'; then
    systemctl enable --now redis-server
  else
    systemctl enable --now redis
  fi
  echo "redis installed and started"
}

memcached_menu() {
  while true; do
    echo
    echo "Memcached management"
    echo "1) Install"
    echo "2) Status"
    echo "3) Start"
    echo "4) Stop"
    echo "5) Restart"
    echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1) cache_install_memcached ;;
      2) systemctl --no-pager -l status memcached || true ;;
      3) systemctl start memcached ;;
      4) systemctl stop memcached ;;
      5) systemctl restart memcached ;;
      0) return ;;
      *) echo "Invalid" ;;
    esac
  done
}

redis_service_name() {
  if systemctl list-unit-files | grep -q '^redis-server\.service'; then
    echo "redis-server"
  else
    echo "redis"
  fi
}

redis_menu() {
  local svc
  svc="$(redis_service_name)"
  while true; do
    echo
    echo "Redis management ($svc)"
    echo "1) Install"
    echo "2) Status"
    echo "3) Start"
    echo "4) Stop"
    echo "5) Restart"
    echo "0) Back"
    read -r -p "Choose: " ch
    case "$ch" in
      1) cache_install_redis; svc="$(redis_service_name)" ;;
      2) systemctl --no-pager -l status "$svc" || true ;;
      3) systemctl start "$svc" ;;
      4) systemctl stop "$svc" ;;
      5) systemctl restart "$svc" ;;
      0) return ;;
      *) echo "Invalid" ;;
    esac
  done
}

while true; do
  echo
  echo "Cache management"
  echo "1) Manage Memcached"
  echo "2) Manage Redis"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) memcached_menu ;;
    2) redis_menu ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
