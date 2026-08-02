#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

require_non_root
require_commands bootctl findmnt mkinitcpio pacman sudo
load_config "$CONFIG_FILE"
validate_config runtime

warn "Read current Arch Linux news for manual-intervention notices before major upgrades."
sudo -v
findmnt -rn /efi >/dev/null 2>&1 \
  || die "/efi is not mounted; refusing to update kernels or boot assets."

sign_boot_assets=false
if bool_true "$ENABLE_SECURE_BOOT" || secure_boot_enabled; then
  require_commands sbctl
  sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem \
    || die "Secure Boot is enabled or expected, but the sbctl db key pair is unavailable; refusing to update."
  sudo test -r /etc/kernel/uki.conf \
    || die "Secure Boot is enabled or expected, but /etc/kernel/uki.conf is missing; run 'sudo archctl secure-boot' before updating."
  sign_boot_assets=true
elif \
  sudo test -r /var/lib/sbctl/keys/db/db.key && \
  sudo test -r /var/lib/sbctl/keys/db/db.pem; then
  require_commands sbctl
  sign_boot_assets=true
fi
sudo pacman -Syu

if bool_true "$ENABLE_AUR" && command -v "$AUR_HELPER" >/dev/null 2>&1; then
  "$AUR_HELPER" -Sua
fi

sudo bootctl --esp-path=/efi update
sudo mkinitcpio -P
if bool_true "$sign_boot_assets"; then
  sudo sbctl sign-all
  sudo sbctl verify
fi

if command -v paccache >/dev/null 2>&1; then
  sudo paccache --remove --keep 3
fi

success "System and signed boot assets are up to date."
