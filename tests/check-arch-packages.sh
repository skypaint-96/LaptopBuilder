#!/usr/bin/env bash
set -Eeuo pipefail

# Intended for the disposable Arch Linux CI container. Build package lists from
# the same configuration/functions used by the installer so tests cannot drift.
[[ -r /etc/arch-release ]] || {
  echo 'check-arch-packages.sh must run inside Arch Linux.' >&2
  exit 1
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"
# shellcheck source=../scripts/install/20-base.sh
source "$ROOT/scripts/install/20-base.sh"

load_config "$ROOT/config/install.conf.example"
validate_config runtime
enable_live_iso_multilib

build_package_lists
all_packages=("${REQUIRED_OFFICIAL_PACKAGES[@]}")

# Also resolve the supported AMD profile so optional profile names do not rot.
CPU_VENDOR=amd
GPU_VENDOR=amd
ENABLE_T480=false
build_package_lists
all_packages+=("${REQUIRED_OFFICIAL_PACKAGES[@]}")

mapfile -t all_packages < <(printf '%s\n' "${all_packages[@]}" | sort -u)
pacman -Sp --noconfirm --print-format '%n' "${all_packages[@]}" >/dev/null
echo "Arch repository package resolution passed for ${#all_packages[@]} package(s)."
