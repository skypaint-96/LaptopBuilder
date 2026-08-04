#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"
# shellcheck source=../scripts/install/20-base.sh
source "$ROOT/scripts/install/20-base.sh"

contains() {
  local wanted=$1 item
  shift
  for item in "$@"; do
    [[ $item == "$wanted" ]] && return 0
  done
  return 1
}

load_config "$ROOT/config/install.conf.example"
validate_config runtime
build_package_lists

for package in base archlinux-keyring linux linux-lts sbctl systemd-ukify steam lib32-gamemode lib32-vulkan-intel dotnet-sdk docker github-cli openssh snapper tlp xdg-utils; do
  contains "$package" "${REQUIRED_OFFICIAL_PACKAGES[@]}" \
    || { echo "Required Intel/T480 package missing: $package" >&2; exit 1; }
done
contains lib32-vulkan-radeon "${REQUIRED_OFFICIAL_PACKAGES[@]}" && {
  echo 'AMD Vulkan package leaked into Intel profile.' >&2
  exit 1
}

CPU_VENDOR=amd
GPU_VENDOR=amd
ENABLE_T480=false
build_package_lists
for package in amd-ucode vulkan-radeon lib32-vulkan-radeon; do
  contains "$package" "${REQUIRED_OFFICIAL_PACKAGES[@]}" \
    || { echo "Required AMD package missing: $package" >&2; exit 1; }
done
contains intel-ucode "${REQUIRED_OFFICIAL_PACKAGES[@]}" && {
  echo 'Intel microcode leaked into AMD profile.' >&2
  exit 1
}

TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/cache" "$TEMP/db/sync"
printf 'cached package\n' > "$TEMP/cache/base-1-1-x86_64.pkg.tar.zst"
printf 'cached package\n' > "$TEMP/cache/bash-1-1-x86_64.pkg.tar.zst"
ARCHWS_PACKAGE_CACHE_DIR="$TEMP/cache"
ARCHWS_SYNC_CACHE_DIR="$TEMP/db/sync"
pacman() {
  printf '%s\n' \
    'https://mirror.example.invalid/core/os/x86_64/base-1-1-x86_64.pkg.tar.zst' \
    'https://mirror.example.invalid/core/os/x86_64/bash-1-1-x86_64.pkg.tar.zst'
}
mapfile -t offline_files < <(resolve_offline_base_package_files)
[[ ${#offline_files[@]} == 2 ]]
[[ ${offline_files[0]} == "$TEMP/cache/base-1-1-x86_64.pkg.tar.zst" ]]
[[ ${offline_files[1]} == "$TEMP/cache/bash-1-1-x86_64.pkg.tar.zst" ]]
unset -f pacman

echo 'Official package-list construction tests passed.'
