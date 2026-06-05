#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE_DIR="$(cd -P -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${BASE_DIR}/scripts/common.sh"

project_config_load || true

project_config_set_many \
  "ADMINER_PORT" "${ADMINER_PORT:-}" \
  "ADMINER_ENABLED" "${ADMINER_ENABLED:-}" \
  "ADMINER_USERNAME" "${ADMINER_USERNAME:-}" \
  "ADMINER_PASSWORD" "${ADMINER_PASSWORD:-}"

if [[ -f "$APP_CONFIG_LEGACY_ADMINER_FILE" ]]; then
  rm -f "$APP_CONFIG_LEGACY_ADMINER_FILE"
fi
