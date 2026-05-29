#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VERSION_FILE_URL_DEFAULT="https://raw.githubusercontent.com/hoangpham5694/LEMP-script/master/builds/release-version.txt"
VERSION_FILE_URL="${VERSION_FILE_URL:-$VERSION_FILE_URL_DEFAULT}"

RELEASE_TAG_DEFAULT_FALLBACK="v1.0.0"
RELEASE_TAG_DEFAULT="$(curl -fsSL "$VERSION_FILE_URL" 2>/dev/null | head -n1 | tr -d '\r' | xargs || true)"
RELEASE_TAG_DEFAULT="${RELEASE_TAG_DEFAULT:-$RELEASE_TAG_DEFAULT_FALLBACK}"

RELEASE_PAGE_DEFAULT="https://github.com/hoangpham5694/LEMP-script/releases/tag/${RELEASE_TAG_DEFAULT}"
ARCHIVE_URL_DEFAULT="https://github.com/hoangpham5694/LEMP-script/archive/refs/tags/${RELEASE_TAG_DEFAULT}.tar.gz"
TARGET_DIR_DEFAULT="/opt/simple-vps"

RELEASE_TAG="${RELEASE_TAG:-$RELEASE_TAG_DEFAULT}"
RELEASE_PAGE="${RELEASE_PAGE:-$RELEASE_PAGE_DEFAULT}"
ARCHIVE_URL="${ARCHIVE_URL:-$ARCHIVE_URL_DEFAULT}"
TARGET_DIR="${TARGET_DIR:-$TARGET_DIR_DEFAULT}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() {
  echo "[install-from-release] $*"
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

main() {
  need_cmd curl
  need_cmd tar

  local tmp archive extract_dir release_root resolved_archive_url
  tmp="$(mktemp -d)"
  archive="${tmp}/release.tar.gz"
  extract_dir="${tmp}/extract"

  log "Release page: ${RELEASE_PAGE}"
  resolved_archive_url="$(resolve_archive_url "$RELEASE_TAG" || true)"
  if [[ -z "$resolved_archive_url" ]]; then
    resolved_archive_url="$ARCHIVE_URL"
  fi
  log "Downloading archive: ${resolved_archive_url}"
  curl -fL "$resolved_archive_url" -o "$archive"

  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"

  release_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$release_root" ]] || { echo "Cannot locate extracted release directory" >&2; exit 1; }

  [[ -f "${release_root}/src/install.sh" ]] || { echo "Missing src/install.sh in release" >&2; exit 1; }
  [[ -f "${release_root}/src/simple-vps.sh" ]] || { echo "Missing src/simple-vps.sh in release" >&2; exit 1; }

  log "Installing release ${RELEASE_TAG} into ${TARGET_DIR}"
  $SUDO rm -rf "$TARGET_DIR"
  $SUDO mkdir -p "$TARGET_DIR"
  $SUDO cp -a "${release_root}/." "$TARGET_DIR/"

  log "Starting installer..."
  $SUDO bash "$TARGET_DIR/src/install.sh"

  rm -rf "$tmp"
}

main "$@"
