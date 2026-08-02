#!/usr/bin/env bash
set -Eeuo pipefail

# Run in a disposable Arch container. Package selection comes from the same
# function used by pacstrap and the offline-cache builder.
[[ -r /etc/arch-release ]] || {
  echo 'check-arch-packages.sh must run inside Arch Linux.' >&2
  exit 1
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/packages.sh
source "$ROOT/scripts/lib/packages.sh"

sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm >/dev/null

all_packages=()
load_config "$ROOT/config/install.conf.example"
collect_official_packages selected
all_packages+=("${selected[@]}")

CPU_VENDOR=amd
GPU_VENDOR=amd
ENABLE_T480=false
collect_official_packages selected
all_packages+=("${selected[@]}")

GPU_VENDOR=generic
ENABLE_GAMING=false
collect_official_packages selected
all_packages+=("${selected[@]}")

mapfile -t packages < <(printf '%s\n' "${all_packages[@]}" | LC_ALL=C sort -u)
pacman -Sp --noconfirm --print-format '%n' "${packages[@]}" >/dev/null
echo "Arch repository package resolution passed for ${#packages[@]} package(s)."
