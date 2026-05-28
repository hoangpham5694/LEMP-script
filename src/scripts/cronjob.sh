#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

list_cronjobs() {
  echo "Current root cronjobs:"
  crontab -l 2>/dev/null || echo "(empty)"
}

add_cronjob() {
  local schedule cmd line tmp
  read -r -p "Enter cron schedule (e.g. */5 * * * *): " schedule
  [[ -n "$schedule" ]] || { echo "Schedule is required"; return; }
  read -r -p "Enter command: " cmd
  [[ -n "$cmd" ]] || { echo "Command is required"; return; }

  line="${schedule} ${cmd}"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null > "$tmp" || true
  echo "$line" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "Cronjob added"
}

edit_cronjob() {
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null > "$tmp" || true
  if [[ ! -s "$tmp" ]]; then
    echo "No cronjobs to edit"
    rm -f "$tmp"
    return
  fi

  if command -v nano >/dev/null 2>&1; then
    nano "$tmp"
  elif command -v vi >/dev/null 2>&1; then
    vi "$tmp"
  else
    echo "No editor found (nano/vi)"
    rm -f "$tmp"
    return
  fi

  crontab "$tmp"
  rm -f "$tmp"
  echo "Cronjobs updated"
}

delete_cronjob() {
  local tmp idx line_no total
  tmp="$(mktemp)"
  crontab -l 2>/dev/null > "$tmp" || true
  if [[ ! -s "$tmp" ]]; then
    echo "No cronjobs to delete"
    rm -f "$tmp"
    return
  fi

  echo "Select cronjob to delete:"
  nl -ba "$tmp"
  total="$(wc -l < "$tmp" | tr -d ' ')"
  read -r -p "Enter line number (1-${total}): " idx
  [[ "$idx" =~ ^[0-9]+$ ]] || { echo "Invalid number"; rm -f "$tmp"; return; }
  (( idx >= 1 && idx <= total )) || { echo "Out of range"; rm -f "$tmp"; return; }

  line_no="$idx"
  sed -i.bak "${line_no}d" "$tmp"
  rm -f "$tmp.bak"
  crontab "$tmp"
  rm -f "$tmp"
  echo "Cronjob deleted"
}

while true; do
  echo
  echo "Cronjob management"
  echo "1) List cronjobs"
  echo "2) Add cronjob"
  echo "3) Edit cronjobs"
  echo "4) Delete cronjob"
  echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) list_cronjobs ;;
    2) add_cronjob ;;
    3) edit_cronjob ;;
    4) delete_cronjob ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
