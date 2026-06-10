#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE_DIR="$(cd -P -- "${SCRIPT_DIR}/../.." && pwd -P)"
source "${BASE_DIR}/scripts/common.sh"

project_config_load || true

if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  project_config_set "MYSQL_ROOT_PASSWORD" "$MYSQL_ROOT_PASSWORD"
fi
