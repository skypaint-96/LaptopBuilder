#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

require_non_root
require_commands findmnt pacman sudo
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run updates as configured user '$USERNAME'."

trap stop_sudo_keepalive EXIT
warn "Read current Arch Linux news for manual-intervention notices before major upgrades."
info "Opening one sudo session for the complete official/AUR/boot update."
start_sudo_keepalive

findmnt -rn /efi >/dev/null 2>&1 \
  || die "/efi is not mounted; refusing to update kernels or boot assets."

sign_boot_assets=false
if bool_true "$ENABLE_SECURE_BOOT" || secure_boot_enabled; then
  require_commands sbctl
  sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem \
    || die "Secure Boot is enabled or expected, but the sbctl db key pair is unavailable; refusing to update."
  sudo test -r /etc/kernel/uki.conf \
    || die "Secure Boot is enabled or expected, but /etc/kernel/uki.conf is missing; run 'archctl secure-boot' before updating."
  sign_boot_assets=true
elif sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem; then
  sign_boot_assets=true
fi

declare -a pacman_args=(-Syu)
if bool_true "$PROVISION_NONINTERACTIVE"; then
  pacman_args+=(--noconfirm)
fi
sudo pacman "${pacman_args[@]}"

if bool_true "$ENABLE_AUR" && command -v "$AUR_HELPER" >/dev/null 2>&1; then
  declare -a aur_args=(-Sua --needed)
  if bool_true "$AUR_NONINTERACTIVE"; then
    aur_args+=(--noconfirm --skipreview)
  fi
  "$AUR_HELPER" "${aur_args[@]}"
fi

if bool_true "$sign_boot_assets"; then
  sudo env \
    "ARCH_WORKSTATION_ROOT=$REPO_ROOT" \
    "ARCH_WORKSTATION_CONFIG=$CONFIG_FILE" \
    "$REPO_ROOT/scripts/security/secure-boot.sh" --yes --sign-only
fi

if command -v paccache >/dev/null 2>&1; then
  sudo paccache --remove --keep 3
fi

success "Official packages, AUR packages, UKIs, and registered EFI binaries are up to date."
