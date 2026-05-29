#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE_URL_DEFAULT="https://raw.githubusercontent.com/hoangpham5694/LEMP-script/master/builds/release-version.txt"
REPO_ARCHIVE_URL_BASE_DEFAULT="https://github.com/hoangpham5694/LEMP-script/archive/refs/tags"
TARGET_DIR_DEFAULT="/opt/simple-vps"
LOCAL_VERSION_FILE_REL="builds/release-version.txt"

VERSION_FILE_URL="${VERSION_FILE_URL:-$VERSION_FILE_URL_DEFAULT}"
REPO_ARCHIVE_URL_BASE="${REPO_ARCHIVE_URL_BASE:-$REPO_ARCHIVE_URL_BASE_DEFAULT}"
TARGET_DIR="${TARGET_DIR:-$TARGET_DIR_DEFAULT}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() {
  echo "[update-from-release] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

resolve_archive_url() {
  local tag="$1"
  local tag_alt=""
  local url=""
  local candidates=()

  if [[ "$tag" == v* ]]; then
    tag_alt="${tag#v}"
  else
    tag_alt="v${tag}"
  fi

  candidates+=("https://github.com/hoangpham5694/LEMP-script/archive/refs/tags/${tag}.tar.gz")
  candidates+=("https://codeload.github.com/hoangpham5694/LEMP-script/tar.gz/refs/tags/${tag}")
  candidates+=("https://github.com/hoangpham5694/LEMP-script/archive/refs/tags/${tag_alt}.tar.gz")
  candidates+=("https://codeload.github.com/hoangpham5694/LEMP-script/tar.gz/refs/tags/${tag_alt}")

  for url in "${candidates[@]}"; do
    if curl -fsIL "$url" >/dev/null 2>&1; then
      echo "$url"
      return 0
    fi
  done

  return 1
}

normalize_version() {
  local v="$1"
  printf '%s' "$v" | tr -d '\r' | xargs
}

version_lt() {
  local a b
  a="${1#v}"
  b="${2#v}"
  [[ "$a" != "$b" ]] && [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" == "$a" ]]
}

get_local_version() {
  local local_file
  local_file="${TARGET_DIR}/${LOCAL_VERSION_FILE_REL}"
  if [[ -f "$local_file" ]]; then
    normalize_version "$(head -n1 "$local_file")"
  else
    echo ""
  fi
}

get_remote_version() {
  normalize_version "$(curl -fsSL "$VERSION_FILE_URL" | head -n1)"
}

update_local_files() {
  local remote_version="$1"
  local archive_url tmp archive extract_dir release_root

  archive_url="$(resolve_archive_url "$remote_version" || true)"
  [[ -n "$archive_url" ]] || archive_url="${REPO_ARCHIVE_URL_BASE}/${remote_version}.tar.gz"
  tmp="$(mktemp -d)"
  archive="${tmp}/release.tar.gz"
  extract_dir="${tmp}/extract"

  log "Downloading release archive: ${archive_url}"
  curl -fL "$archive_url" -o "$archive"

  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"

  release_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$release_root" ]] || { echo "Cannot locate extracted release directory" >&2; exit 1; }
  [[ -f "${release_root}/src/install.sh" ]] || { echo "Missing src/install.sh in release" >&2; exit 1; }

  log "Overwriting local files in ${TARGET_DIR}"
  $SUDO mkdir -p "$TARGET_DIR"
  $SUDO cp -a "${release_root}/." "$TARGET_DIR/"
}

sync_runtime_files() {
  local src_dir
  src_dir="${TARGET_DIR}/src"

  [[ -f "${src_dir}/simple-vps.sh" ]] || { echo "Missing ${src_dir}/simple-vps.sh" >&2; exit 1; }
  [[ -d "${src_dir}/scripts" ]] || { echo "Missing ${src_dir}/scripts" >&2; exit 1; }

  log "Sync runtime scripts to /usr/local/bin and /usr/local/share/simple-vps"
  $SUDO install -m 755 "${src_dir}/simple-vps.sh" /usr/local/bin/simple-vps
  $SUDO mkdir -p /usr/local/share/simple-vps/{scripts,templates,libs}
  $SUDO cp -a "${src_dir}/scripts/." /usr/local/share/simple-vps/scripts/
  $SUDO cp -a "${src_dir}/templates/." /usr/local/share/simple-vps/templates/
  if [[ -f "${src_dir}/libs/adminer-5.4.2.php" ]]; then
    $SUDO install -m 644 "${src_dir}/libs/adminer-5.4.2.php" /usr/local/share/simple-vps/libs/adminer-5.4.2.php
  fi
  $SUDO chmod +x /usr/local/share/simple-vps/scripts/*.sh
  if [[ -f "${src_dir}/templates/profile/simple-vps.sh" ]]; then
    $SUDO install -m 644 "${src_dir}/templates/profile/simple-vps.sh" /etc/profile.d/simple-vps.sh
  fi

}

main() {
  need_cmd curl
  need_cmd tar
  need_cmd sort

  local local_version remote_version

  remote_version="$(get_remote_version)"
  [[ -n "$remote_version" ]] || { echo "Cannot read remote version" >&2; exit 1; }

  local_version="$(get_local_version)"

  if [[ -z "$local_version" ]]; then
    log "Local version not found at ${TARGET_DIR}/${LOCAL_VERSION_FILE_REL}, updating to ${remote_version}"
    update_local_files "$remote_version"
    sync_runtime_files
    log "Update completed"
    exit 0
  fi

  log "Local version:  ${local_version}"
  log "Remote version: ${remote_version}"

  if [[ "$local_version" == "$remote_version" ]]; then
    log "Already at the latest version (${local_version})."
    exit 0
  fi

  if version_lt "$local_version" "$remote_version"; then
    log "Updating from ${local_version} to ${remote_version}"
    update_local_files "$remote_version"
    sync_runtime_files
    log "Update completed"
    exit 0
  fi

  log "Local version (${local_version}) is newer than remote (${remote_version}), skip update."
}

main "$@"
