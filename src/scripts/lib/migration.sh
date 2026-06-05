#!/bin/bash
set -euo pipefail

project_migration_current_version() {
  printf '%s\n' "${MIGRATION_VERSION:-1.0.0}"
}

project_migration_version_gt() {
  local left="${1#v}"
  local right="${2#v}"

  [[ "$left" != "$right" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | head -n1)" == "$right" ]]
}

project_migration_run_script() {
  local script="$1"
  echo "[migration] Running: ${script}"
  bash "$script"
}

project_migration_run_version_dir() {
  local version_dir="$1"
  local version_name="${version_dir##*/}"
  local script scripts=()

  shopt -s nullglob
  scripts=("${version_dir}"/*.sh)
  shopt -u nullglob

  if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "[migration] No scripts found in ${version_name}, marking as applied"
  else
    for script in "${scripts[@]}"; do
      project_migration_run_script "$script"
    done
  fi

  project_config_set "MIGRATION_VERSION" "$version_name"
  MIGRATION_VERSION="$version_name"
  echo "[migration] Applied version: ${version_name}"
}

project_migration_run_pending() {
  local current_version migration_root version_dir version_name

  current_version="$(project_migration_current_version)"
  migration_root="${MIGRATION_DIR:-}"

  [[ -n "$migration_root" ]] || { echo "[migration] MIGRATION_DIR is empty"; return 1; }
  [[ -d "$migration_root" ]] || { echo "[migration] Migration dir not found: ${migration_root}"; return 0; }

  while IFS= read -r version_dir; do
    [[ -n "$version_dir" ]] || continue
    version_name="${version_dir##*/}"
    [[ "$version_name" =~ ^[0-9]+([.][0-9]+){1,2}([-.][0-9A-Za-z.-]+)?$ ]] || continue

    if project_migration_version_gt "$version_name" "$current_version"; then
      project_migration_run_version_dir "$version_dir"
      current_version="$version_name"
    fi
  done < <(find "$migration_root" -mindepth 1 -maxdepth 1 -type d | sort -V)
}
