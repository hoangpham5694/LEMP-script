#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE_DIR="$(cd -P -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${BASE_DIR}/scripts/common.sh"

project_config_load || true

legacy_password="${DB_ROOT_PASSWORD:-}"
current_password="${MYSQL_ROOT_PASSWORD:-}"

if [[ -z "$current_password" && -n "$legacy_password" ]]; then
  project_config_set "MYSQL_ROOT_PASSWORD" "$legacy_password"
  current_password="$legacy_password"
fi

if [[ -n "$legacy_password" ]]; then
  project_config_unset "DB_ROOT_PASSWORD"
fi
