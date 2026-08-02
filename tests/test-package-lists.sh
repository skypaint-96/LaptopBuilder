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

for package in base linux linux-lts sbctl systemd-ukify steam lib32-gamemode lib32-vulkan-intel dotnet-sdk docker snapper tlp; do
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

echo 'Official package-list construction tests passed.'
