#!/bin/bash
set -euo pipefail
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
check_root

write_php_site_conf() {
  local site_name="$1" root_dir="$2" php_sock="$3" conf
  conf="$(site_conf_path "$site_name")"
  render_template_to_file "nginx/site-php.conf.tpl" "$conf" \
    "SERVER_NAME=${site_name}" "ROOT_DIR=${root_dir}" "PHP_SOCK=${php_sock}"
}

write_laravel_site_conf() {
  local site_name="$1" root_dir="$2" php_sock="$3" conf
  conf="$(site_conf_path "$site_name")"
  render_template_to_file "nginx/site-laravel.conf.tpl" "$conf" \
    "SERVER_NAME=${site_name}" "ROOT_DIR=${root_dir}" "PHP_SOCK=${php_sock}"
}

prompt_site_info() {
  local site_name site_root default_root
  read -r -p "Enter site name/domain (example: mysite.local): " site_name
  valid_site_name "$site_name" || { echo "Invalid site name"; return 1; }
  default_root="/var/www/${site_name}"
  read -r -p "Enter site root folder (default: ${default_root}): " site_root
  site_root="${site_root:-$default_root}"
  SITE_NAME="$site_name"; SITE_ROOT="$site_root"
}

setup_blank_php_site() {
  local php_sock conf blank_tpl
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  mkdir -p "$SITE_ROOT"
  if [[ ! -f "${SITE_ROOT}/index.php" ]]; then
    blank_tpl="$(resolve_template_path "site/blank-index.php" || true)"
    [[ -n "$blank_tpl" ]] || { echo "Template not found"; return; }
    cp -f "$blank_tpl" "${SITE_ROOT}/index.php"
  fi
  write_php_site_conf "$SITE_NAME" "$SITE_ROOT" "$php_sock"
  conf="$(site_conf_path "$SITE_NAME")"
  reload_nginx
  echo "Blank PHP site created"; echo "Site: $SITE_NAME"; echo "Root: $SITE_ROOT"; echo "Nginx conf: $conf"
}

setup_blank_laravel_site() {
  local php_sock conf laravel_tpl
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  mkdir -p "${SITE_ROOT}/public" "${SITE_ROOT}/storage" "${SITE_ROOT}/bootstrap/cache"
  if [[ ! -f "${SITE_ROOT}/public/index.php" ]]; then
    laravel_tpl="$(resolve_template_path "site/laravel-public-index.php" || true)"
    [[ -n "$laravel_tpl" ]] || { echo "Template not found"; return; }
    cp -f "$laravel_tpl" "${SITE_ROOT}/public/index.php"
  fi
  write_laravel_site_conf "$SITE_NAME" "$SITE_ROOT" "$php_sock"
  conf="$(site_conf_path "$SITE_NAME")"
  reload_nginx
  echo "Blank Laravel site created"; echo "Site: $SITE_NAME"; echo "Root: $SITE_ROOT"; echo "Nginx conf: $conf"
}

setup_wordpress_site() {
  local php_sock conf tmpdir setup_db db_name db_user db_pass user_prefix suffix
  php_sock="$(detect_php_fpm_socket || true)"; [[ -n "$php_sock" ]] || { echo "Cannot detect php-fpm socket."; return; }
  mkdir -p "$SITE_ROOT"
  tmpdir="$(mktemp -d)"
  curl -fsSL https://wordpress.org/latest.tar.gz -o "${tmpdir}/latest.tar.gz"
  tar -xzf "${tmpdir}/latest.tar.gz" -C "$tmpdir"
  cp -a "${tmpdir}/wordpress/." "$SITE_ROOT/"
  rm -rf "$tmpdir"
  write_php_site_conf "$SITE_NAME" "$SITE_ROOT" "$php_sock"
  conf="$(site_conf_path "$SITE_NAME")"
  reload_nginx
  read -r -p "Create database and user for this WordPress site? (Y/n): " setup_db
  setup_db="${setup_db:-Y}"
  if [[ "$setup_db" =~ ^[Yy]$ ]]; then
    read -r -p "Enter database name (default: ${SITE_NAME//[^A-Za-z0-9_]/_}): " db_name
    db_name="${db_name:-${SITE_NAME//[^A-Za-z0-9_]/_}}"
    valid_db_name "$db_name" || { echo "Invalid database name"; return; }
    user_prefix="${db_name:0:10}"; suffix="$(random_alnum 4)"; db_user="${user_prefix}${suffix}"; db_pass="$(random_alnum 20)"
    db_exec_sql "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    db_exec_sql "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    db_exec_sql "ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
    db_exec_sql "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';"
    db_exec_sql "FLUSH PRIVILEGES;"
    if [[ -f "${SITE_ROOT}/wp-config-sample.php" ]]; then
      cp -f "${SITE_ROOT}/wp-config-sample.php" "${SITE_ROOT}/wp-config.php"
      sed -i.bak "s/database_name_here/${db_name}/" "${SITE_ROOT}/wp-config.php"
      sed -i.bak "s/username_here/${db_user}/" "${SITE_ROOT}/wp-config.php"
      sed -i.bak "s/password_here/${db_pass}/" "${SITE_ROOT}/wp-config.php"
      rm -f "${SITE_ROOT}/wp-config.php.bak"
    fi
  fi
  echo "WordPress site created"; echo "Site: $SITE_NAME"; echo "Root: $SITE_ROOT"; echo "Nginx conf: $conf"
  if [[ "${setup_db:-N}" =~ ^[Yy]$ ]]; then
    echo "Database: $db_name"; echo "Database user: $db_user"; echo "Database password: $db_pass"; echo "Database host: localhost"
  fi
}

while true; do
  echo; echo "Create site"
  echo "1) New wordpress site"; echo "2) New blank site"; echo "3) New blank site for laravel"; echo "0) Back"
  read -r -p "Choose: " ch
  case "$ch" in
    1) prompt_site_info && setup_wordpress_site ;;
    2) prompt_site_info && setup_blank_php_site ;;
    3) prompt_site_info && setup_blank_laravel_site ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
  esac
done
