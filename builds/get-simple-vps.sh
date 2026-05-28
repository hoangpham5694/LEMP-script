#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE_DEFAULT="https://raw.githubusercontent.com/hoangpham5694/LEMP-script/main"
TARGET_DIR_DEFAULT="/opt/simple-vps"

REPO_RAW_BASE="${REPO_RAW_BASE:-$REPO_RAW_BASE_DEFAULT}"
TARGET_DIR="${TARGET_DIR:-$TARGET_DIR_DEFAULT}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() {
  echo "[get-simple-vps] $*"
}

download() {
  local url="$1"
  local out="$2"
  log "Downloading: $url"
  if ! curl -fsSL "$url" -o "$out"; then
    echo "Failed to download: $url" >&2
    exit 1
  fi
}

verify_required_files() {
  local missing=0
  local required=(
    "$TARGET_DIR/install.sh"
    "$TARGET_DIR/simple-vps.sh"
    "$TARGET_DIR/libs/adminer-5.4.2.php"
    "$TARGET_DIR/templates/nginx/adminer.conf.tpl"
    "$TARGET_DIR/templates/nginx/site-php.conf.tpl"
    "$TARGET_DIR/templates/nginx/site-laravel.conf.tpl"
    "$TARGET_DIR/templates/site/blank-index.php"
    "$TARGET_DIR/templates/site/laravel-public-index.php"
    "$TARGET_DIR/templates/profile/simple-vps.sh"
    "$TARGET_DIR/scripts/common.sh"
    "$TARGET_DIR/scripts/nginx.sh"
    "$TARGET_DIR/scripts/database.sh"
    "$TARGET_DIR/scripts/adminer.sh"
    "$TARGET_DIR/scripts/site.sh"
    "$TARGET_DIR/scripts/firewall.sh"
    "$TARGET_DIR/scripts/cache.sh"
    "$TARGET_DIR/scripts/tools.sh"
    "$TARGET_DIR/scripts/cronjob.sh"
  )

  for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "Missing required file: $f" >&2
      missing=1
    fi
  done

  (( missing == 0 )) || exit 1
}

main() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required" >&2
    exit 1
  fi

  log "Installing into: $TARGET_DIR"
  $SUDO mkdir -p "$TARGET_DIR/libs" "$TARGET_DIR/templates/nginx" "$TARGET_DIR/templates/site" "$TARGET_DIR/templates/profile" "$TARGET_DIR/scripts"

  download "$REPO_RAW_BASE/src/install.sh" "/tmp/simple-vps-install.sh"
  download "$REPO_RAW_BASE/src/simple-vps.sh" "/tmp/simple-vps-menu.sh"
  download "$REPO_RAW_BASE/src/scripts/common.sh" "/tmp/simple-vps-common.sh"
  download "$REPO_RAW_BASE/src/scripts/nginx.sh" "/tmp/simple-vps-nginx.sh"
  download "$REPO_RAW_BASE/src/scripts/database.sh" "/tmp/simple-vps-database.sh"
  download "$REPO_RAW_BASE/src/scripts/adminer.sh" "/tmp/simple-vps-adminer.sh"
  download "$REPO_RAW_BASE/src/scripts/site.sh" "/tmp/simple-vps-site.sh"
  download "$REPO_RAW_BASE/src/scripts/firewall.sh" "/tmp/simple-vps-firewall.sh"
  download "$REPO_RAW_BASE/src/scripts/cache.sh" "/tmp/simple-vps-cache.sh"
  download "$REPO_RAW_BASE/src/scripts/tools.sh" "/tmp/simple-vps-tools.sh"
  download "$REPO_RAW_BASE/src/scripts/cronjob.sh" "/tmp/simple-vps-cronjob.sh"
  download "$REPO_RAW_BASE/src/libs/adminer-5.4.2.php" "/tmp/adminer-5.4.2.php"
  download "$REPO_RAW_BASE/src/templates/nginx/adminer.conf.tpl" "/tmp/adminer.conf.tpl"
  download "$REPO_RAW_BASE/src/templates/nginx/site-php.conf.tpl" "/tmp/site-php.conf.tpl"
  download "$REPO_RAW_BASE/src/templates/nginx/site-laravel.conf.tpl" "/tmp/site-laravel.conf.tpl"
  download "$REPO_RAW_BASE/src/templates/site/blank-index.php" "/tmp/blank-index.php"
  download "$REPO_RAW_BASE/src/templates/site/laravel-public-index.php" "/tmp/laravel-public-index.php"
  download "$REPO_RAW_BASE/src/templates/profile/simple-vps.sh" "/tmp/profile-simple-vps.sh"

  $SUDO install -m 755 "/tmp/simple-vps-install.sh" "$TARGET_DIR/install.sh"
  $SUDO install -m 755 "/tmp/simple-vps-menu.sh" "$TARGET_DIR/simple-vps.sh"
  $SUDO install -m 755 "/tmp/simple-vps-common.sh" "$TARGET_DIR/scripts/common.sh"
  $SUDO install -m 755 "/tmp/simple-vps-nginx.sh" "$TARGET_DIR/scripts/nginx.sh"
  $SUDO install -m 755 "/tmp/simple-vps-database.sh" "$TARGET_DIR/scripts/database.sh"
  $SUDO install -m 755 "/tmp/simple-vps-adminer.sh" "$TARGET_DIR/scripts/adminer.sh"
  $SUDO install -m 755 "/tmp/simple-vps-site.sh" "$TARGET_DIR/scripts/site.sh"
  $SUDO install -m 755 "/tmp/simple-vps-firewall.sh" "$TARGET_DIR/scripts/firewall.sh"
  $SUDO install -m 755 "/tmp/simple-vps-cache.sh" "$TARGET_DIR/scripts/cache.sh"
  $SUDO install -m 755 "/tmp/simple-vps-tools.sh" "$TARGET_DIR/scripts/tools.sh"
  $SUDO install -m 755 "/tmp/simple-vps-cronjob.sh" "$TARGET_DIR/scripts/cronjob.sh"
  $SUDO install -m 644 "/tmp/adminer-5.4.2.php" "$TARGET_DIR/libs/adminer-5.4.2.php"
  $SUDO install -m 644 "/tmp/adminer.conf.tpl" "$TARGET_DIR/templates/nginx/adminer.conf.tpl"
  $SUDO install -m 644 "/tmp/site-php.conf.tpl" "$TARGET_DIR/templates/nginx/site-php.conf.tpl"
  $SUDO install -m 644 "/tmp/site-laravel.conf.tpl" "$TARGET_DIR/templates/nginx/site-laravel.conf.tpl"
  $SUDO install -m 644 "/tmp/blank-index.php" "$TARGET_DIR/templates/site/blank-index.php"
  $SUDO install -m 644 "/tmp/laravel-public-index.php" "$TARGET_DIR/templates/site/laravel-public-index.php"
  $SUDO install -m 644 "/tmp/profile-simple-vps.sh" "$TARGET_DIR/templates/profile/simple-vps.sh"

  rm -f /tmp/simple-vps-install.sh /tmp/simple-vps-menu.sh /tmp/simple-vps-common.sh \
    /tmp/simple-vps-nginx.sh /tmp/simple-vps-database.sh /tmp/simple-vps-adminer.sh \
    /tmp/simple-vps-site.sh /tmp/simple-vps-firewall.sh /tmp/simple-vps-cache.sh /tmp/simple-vps-tools.sh /tmp/simple-vps-cronjob.sh /tmp/adminer-5.4.2.php \
    /tmp/adminer.conf.tpl /tmp/site-php.conf.tpl /tmp/site-laravel.conf.tpl \
    /tmp/blank-index.php /tmp/laravel-public-index.php /tmp/profile-simple-vps.sh

  verify_required_files

  log "Starting installer..."
  $SUDO bash "$TARGET_DIR/install.sh"
}

main "$@"
