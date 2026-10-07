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
sign_with_security_command=false
if bool_true "$ENABLE_SECURE_BOOT" || secure_boot_enabled; then
  require_commands sbctl
  sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem \
    || die "Secure Boot is enabled or expected, but the sbctl db key pair is unavailable; refusing to update."
  sudo test -r /etc/kernel/uki.conf \
    || die "Secure Boot is enabled or expected, but /etc/kernel/uki.conf is missing; run 'archctl secure-boot' before updating."
  sign_boot_assets=true
  sign_with_security_command=true
elif sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem; then
  # Prepared keys may still sign UKIs even before Secure Boot is enabled.
  # secure-boot.sh refuses this configuration when ENABLE_SECURE_BOOT=false.
  sign_boot_assets=true
fi

refresh_boot_assets() {
  if bool_true "$sign_with_security_command"; then
    sudo env \
      "ARCH_WORKSTATION_ROOT=$REPO_ROOT" \
      "ARCH_WORKSTATION_CONFIG=$CONFIG_FILE" \
      "$REPO_ROOT/scripts/security/secure-boot.sh" --yes --sign-only
  else
    sudo env \
      "ARCH_WORKSTATION_ROOT=$REPO_ROOT" \
      "ARCH_WORKSTATION_CONFIG=$CONFIG_FILE" \
      bash -c 'source "$ARCH_WORKSTATION_ROOT/scripts/security/common.sh"; load_runtime_security; rebuild_and_sign_ukis'
  fi
}

# No persistent stage marker: rerunning starts with pacman -Syu and then repeats
# the remaining idempotent stages. In particular, never skip boot repair because
# a previous invocation reached the AUR stage.
boot_stage_pending=false
repair_boot_on_error() {
  local status=$1
  trap - ERR
  if bool_true "$boot_stage_pending" && bool_true "$sign_boot_assets"; then
    warn "Update failed after the official upgrade began; attempting to rebuild and sign boot assets before exiting."
    if ! refresh_boot_assets; then
      warn "Boot repair also failed. Do not reboot until UKIs/signatures are repaired; see docs/RECOVERY.md."
    fi
  fi
  exit "$status"
}
trap 'repair_boot_on_error "$?"' ERR

declare -a pacman_args=(-Syu)
if bool_true "$PROVISION_NONINTERACTIVE"; then
  pacman_args+=(--noconfirm)
fi
info "Stage 1/4: upgrading official packages (safe to rerun after interruption)."
boot_stage_pending=true
sudo pacman "${pacman_args[@]}"

info "Stage 2/4: rebuilding and signing boot assets after the official upgrade."
if bool_true "$sign_boot_assets"; then
  refresh_boot_assets
else
  warn "Secure Boot signing is not configured; package kernel hooks remain responsible for UKI generation."
fi
boot_stage_pending=false

info "Stage 3/4: refreshing the AUR helper and allow-list."
if bool_true "$ENABLE_AUR"; then
  # An official pacman upgrade can change libalpm's ABI. Revalidate or rebuild
  # the configured helper before invoking it, then update remaining AUR packages.
  "$REPO_ROOT/scripts/install-aur.sh"
  declare -a aur_args=(-Sua --needed)
  if bool_true "$AUR_NONINTERACTIVE"; then
    aur_args+=(--noconfirm --skipreview)
  fi
  "$AUR_HELPER" "${aur_args[@]}"
fi

info "Stage 4/4: trimming the package cache when paccache is available."
if command -v paccache >/dev/null 2>&1; then
  sudo paccache --remove --keep 3
fi

success "Update stages completed; rerun archctl update to resume after any future interruption."
