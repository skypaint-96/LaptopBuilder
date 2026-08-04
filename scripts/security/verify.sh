#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_runtime_security
require_commands bootctl cryptsetup findmnt lsblk pacman sbctl systemctl

failures=0
warnings=0

check_ok() { printf '[ OK ] %s\n' "$*"; }
check_fail() { printf '[FAIL] %s\n' "$*" >&2; ((failures += 1)); }
check_warn() { printf '[WARN] %s\n' "$*" >&2; ((warnings += 1)); }

run_check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    check_ok "$description"
  else
    check_fail "$description"
  fi
}

is_x86_64() { [[ $(uname -m) == x86_64 ]]; }
is_uefi() { [[ -d /sys/firmware/efi/efivars ]]; }
efi_mounted() { findmnt -rn /efi; }
root_is_btrfs() { [[ $(findmnt -n -o FSTYPE /) == btrfs ]]; }
root_is_subvol_at() { findmnt -n -o OPTIONS / | tr ',' '\n' | grep -qx 'subvol=/@'; }
has_ukis() { compgen -G '/efi/EFI/Linux/*.efi' >/dev/null; }
network_enabled() { systemctl is-enabled NetworkManager.service; }
display_enabled() { systemctl is-enabled lightdm.service; }
user_exists() { id "$USERNAME"; }
package_installed() { pacman -Q "$1"; }
pending_credentials_removed() {
  [[ ! -s /var/lib/arch-workstation/pending-credentials/luks-passphrase \
    && ! -s /var/lib/arch-workstation/pending-credentials/tpm2-pin ]]
}

check_package() {
  run_check "Package '$1' is installed" package_installed "$1"
}

run_check "x86-64 architecture" is_x86_64
run_check "UEFI boot" is_uefi
run_check "ESP mounted at /efi" efi_mounted
run_check "Btrfs root filesystem" root_is_btrfs
run_check "Btrfs root subvolume is @" root_is_subvol_at
run_check "At least one UKI exists" has_ukis
run_check "NetworkManager is enabled" network_enabled
run_check "LightDM is enabled" display_enabled
run_check "Configured user exists" user_exists
run_check "Provisioning completed marker exists" test -f "$STATE_DIR/provisioned"

luks_device=$(resolve_luks_device)
if cryptsetup isLuks --type luks2 "$luks_device" >/dev/null 2>&1; then
  check_ok "Encrypted root partition is LUKS2"
else
  check_fail "Encrypted root partition is LUKS2"
fi

if bool_true "$ENABLE_SECURE_BOOT"; then
  if setup_mode_enabled; then
    check_fail "Firmware has left Secure Boot Setup Mode"
  else
    check_ok "Firmware has left Secure Boot Setup Mode"
  fi
  if secure_boot_enabled; then
    check_ok "Secure Boot is active"
  else
    check_fail "Secure Boot is active"
  fi
  if secure_boot_keys_present && ESP_PATH=/efi sbctl verify >/dev/null 2>&1; then
    check_ok "EFI binaries verify against the sbctl db key"
  else
    check_fail "EFI binaries verify against the sbctl db key"
  fi
fi

if bool_true "$ENABLE_TPM"; then
  if tpm_token_present "$luks_device"; then
    check_ok "LUKS2 contains a systemd TPM2 token"
  else
    check_fail "LUKS2 contains a systemd TPM2 token"
  fi
  if tpm_unlock_configured; then
    check_ok "Initramfs crypttab requests TPM2 unlock"
  else
    check_fail "Initramfs crypttab requests TPM2 unlock"
  fi
  run_check "Temporary TPM enrollment credentials have been removed" pending_credentials_removed
fi

for package in git vim dotnet-sdk gnome-keyring; do
  check_package "$package"
done

if bool_true "$ENABLE_AUR"; then
  run_check "AUR helper command '$AUR_HELPER' is available" command -v "$AUR_HELPER"
  read -r -a aur_packages <<< "$AUR_PACKAGES"
  for package in "${aur_packages[@]}"; do
    check_package "$package"
  done
fi

check_package github-cli
run_check "Console keyboard layout matches configuration" grep -qxF "KEYMAP=$KEYMAP" /etc/vconsole.conf
run_check "X11 keyboard layout matches configuration" grep -Eq "Option[[:space:]]+\"XkbLayout\"[[:space:]]+\"$X11_LAYOUT\"" /etc/X11/xorg.conf.d/00-keyboard.conf

if bool_true "$ENABLE_DOCKER"; then
  for package in docker docker-buildx docker-compose; do
    check_package "$package"
  done
  run_check "Docker service is enabled" systemctl is-enabled docker.service
  if bool_true "$DOCKER_ADD_USER_TO_GROUP" && id -nG "$USERNAME" | tr ' ' '\n' | grep -qx docker; then
    check_ok "$USERNAME is in the docker group"
  elif bool_true "$DOCKER_ADD_USER_TO_GROUP"; then
    check_fail "$USERNAME is in the docker group"
  fi
fi

if bool_true "$ENABLE_GAMING"; then
  check_package steam
  case "$GPU_VENDOR" in
    intel) check_package lib32-vulkan-intel ;;
    amd) check_package lib32-vulkan-radeon ;;
  esac
fi

if bool_true "$ENABLE_SNAPSHOTS"; then
  check_package snapper
  check_package snap-pac
  run_check "Snapper root configuration exists" test -r /etc/snapper/configs/root
  run_check "Snapper root configuration is registered" grep -Eq '^SNAPPER_CONFIGS=.*root' /etc/conf.d/snapper
  run_check "Snapper timeline timer is enabled" systemctl is-enabled snapper-timeline.timer
fi

if bool_true "$ENABLE_T480"; then
  for package in fwupd smartmontools thermald tlp; do
    check_package "$package"
  done
  for unit in tlp.service thermald.service fwupd-refresh.timer smartd.service; do
    run_check "$unit is enabled" systemctl is-enabled "$unit"
  done
fi

if bool_true "$ENABLE_SSH"; then
  run_check "OpenSSH server is enabled by policy" systemctl is-enabled sshd.service
  run_check "OpenSSH server is running by policy" systemctl is-active sshd.service
elif systemctl is-enabled sshd.service >/dev/null 2>&1; then
  check_warn "OpenSSH server is enabled although ENABLE_SSH=false"
else
  check_ok "OpenSSH server remains disabled"
fi

printf '\nBoot status (informational):\n'
bootctl --no-pager status || check_warn "bootctl status returned a non-zero result"

printf '\nVerification result: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
((failures == 0)) || exit 1
