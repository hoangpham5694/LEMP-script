#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

detect_pm() { command -v apt-get >/dev/null 2>&1 && echo apt || { command -v dnf >/dev/null 2>&1 && echo dnf || echo unknown; }; }
firewall_install() {
  case "$(detect_pm)" in
    apt) apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y firewalld ;;
    dnf) dnf install -y firewalld ;;
    *) echo "Unsupported package manager"; return 1 ;;
  esac
  systemctl enable --now firewalld; firewall-cmd --reload
}
firewall_status() { systemctl --no-pager -l status firewalld || true; firewall-cmd --state 2>/dev/null || true; firewall-cmd --get-default-zone 2>/dev/null || true; }
firewall_add_port() { local p pr z; read -r -p "Enter port: " p; [[ "$p" =~ ^[0-9]+$ ]] && ((p>=1&&p<=65535)) || { echo invalid; return; }; read -r -p "Protocol [tcp/udp] (default: tcp): " pr; pr="${pr:-tcp}"; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --add-port="${p}/${pr}"; firewall-cmd --reload; }
firewall_remove_port() { local p pr z; read -r -p "Enter port: " p; [[ "$p" =~ ^[0-9]+$ ]] && ((p>=1&&p<=65535)) || { echo invalid; return; }; read -r -p "Protocol [tcp/udp] (default: tcp): " pr; pr="${pr:-tcp}"; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --remove-port="${p}/${pr}"; firewall-cmd --reload; }
firewall_allow_ip() { local ip z; read -r -p "Enter IP/CIDR to allow: " ip; [[ -n "$ip" ]] || return; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --add-rich-rule="rule family='ipv4' source address='${ip}' accept"; firewall-cmd --reload; }
firewall_remove_allow_ip() { local ip z; read -r -p "Enter IP/CIDR to remove from allow list: " ip; [[ -n "$ip" ]] || return; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --remove-rich-rule="rule family='ipv4' source address='${ip}' accept"; firewall-cmd --reload; }
firewall_block_ip() { local ip z; read -r -p "Enter IP/CIDR to blacklist: " ip; [[ -n "$ip" ]] || return; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --add-rich-rule="rule family='ipv4' source address='${ip}' drop"; firewall-cmd --reload; }
firewall_unblock_ip() { local ip z; read -r -p "Enter IP/CIDR to remove from blacklist: " ip; [[ -n "$ip" ]] || return; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --remove-rich-rule="rule family='ipv4' source address='${ip}' drop"; firewall-cmd --reload; }
firewall_list_rules() { local z; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --zone="$z" --list-all; }
firewall_allow_web_quick() { local z; read -r -p "Zone (default: public): " z; z="${z:-public}"; firewall-cmd --permanent --zone="$z" --add-service=http; firewall-cmd --permanent --zone="$z" --add-service=https; firewall-cmd --reload; }
firewall_reset_zone_default() { local z c; read -r -p "Zone to reset (default: public): " z; z="${z:-public}"; read -r -p "Continue? (yes/NO): " c; [[ "$c" == "yes" ]] || { echo Cancelled; return; }; firewall-cmd --permanent --zone="$z" --load-zone-defaults; firewall-cmd --reload; }

while true; do
  echo; echo "Firewall management (firewalld)"
  echo "1) Install firewalld"; echo "2) Status"; echo "3) Start firewalld"; echo "4) Stop firewalld"; echo "5) Restart firewalld";
  echo "6) Add port (allow)"; echo "7) Remove port"; echo "8) Add IP to allow list"; echo "9) Remove IP from allow list";
  echo "10) Add IP to blacklist"; echo "11) Remove IP from blacklist"; echo "12) List rules"; echo "13) Allow HTTP/HTTPS quick"; echo "14) Reset rules to default"; echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) firewall_install ;;
    2) firewall_status ;;
    3) systemctl start firewalld ;;
    4) systemctl stop firewalld ;;
    5) systemctl restart firewalld ;;
    6) firewall_add_port ;;
    7) firewall_remove_port ;;
    8) firewall_allow_ip ;;
    9) firewall_remove_allow_ip ;;
    10) firewall_block_ip ;;
    11) firewall_unblock_ip ;;
    12) firewall_list_rules ;;
    13) firewall_allow_web_quick ;;
    14) firewall_reset_zone_default ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
