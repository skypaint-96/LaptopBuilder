#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/usb-common.sh
source "$REPO_ROOT/usb/lib/usb-common.sh"

USB_ROOT="${MASON_USB_ROOT:-}"

usage() {
  cat <<'USAGE'
Usage: ./usb/verify-usb.sh [--usb-root PATH]

Checks boot files, both Arch slots, repository generations, configuration, and
any optional package caches. It does not modify the USB.
USAGE
}

while (($#)); do
  case "$1" in
    --usb-root) [[ $# -ge 2 ]] || usb_die "--usb-root requires a path"; USB_ROOT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usb_die "Unknown option: $1" ;;
  esac
done

[[ -n $USB_ROOT ]] || USB_ROOT=$(usb_find_root) || usb_die "Installer USB not found."
usb_verify_layout "$USB_ROOT" || usb_die "Invalid installer USB layout: $USB_ROOT"
LAYOUT=$(usb_layout_dir "$USB_ROOT")
usb_load_config "$LAYOUT/config/usb.conf"
usb_require_commands awk grep sed sha256sum tar

[[ -s $USB_ROOT/EFI/BOOT/BOOTX64.EFI ]] || usb_die "UEFI fallback loader is missing."
[[ -s $USB_ROOT/boot/grub/grub.cfg ]] || usb_die "GRUB configuration is missing."
grep -q 'archisobasedir=arch-a' "$USB_ROOT/boot/grub/grub.cfg" \
  || usb_die "GRUB does not contain Arch slot a."
grep -q 'archisobasedir=arch-b' "$USB_ROOT/boot/grub/grub.cfg" \
  || usb_die "GRUB does not contain Arch slot b."
usb_ok "UEFI loader and GRUB configuration are present."

for slot in a b; do
  usb_verify_arch_slot "$USB_ROOT" "$slot" || usb_die "Arch slot $slot failed validation."
  usb_ok "Arch slot $slot is complete: $(tr -d '\r\n' < "$USB_ROOT/arch-$slot/version")"
done

verify_repo_generation() {
  local name=$1 archive
  archive="$LAYOUT/cache/repository/$name.tar.gz"
  usb_verify_repository_archive "$archive" "$LAYOUT/cache/repository/$name.sha256"
}

current_repository_valid=false
previous_repository_valid=false
if verify_repo_generation current; then
  current_repository_valid=true
  usb_ok "Current repository snapshot passed checksum and structure validation."
else
  usb_warn "Current repository snapshot failed checksum or structure validation."
fi
if verify_repo_generation previous; then
  previous_repository_valid=true
  usb_ok "Previous repository snapshot passed checksum and structure validation."
else
  usb_warn "Previous repository snapshot failed checksum or structure validation."
fi
if [[ $current_repository_valid != true && $previous_repository_valid != true ]]; then
  usb_die "No usable repository snapshot is present."
fi
if [[ $current_repository_valid != true ]]; then
  usb_warn "Startup will fall back to the previous verified repository generation."
fi

if [[ -d $LAYOUT/cache/pacman ]]; then
  usb_verify_directory_manifest "$LAYOUT/cache/pacman" \
    || usb_die "Official package-cache checksum verification failed."
  [[ -s $LAYOUT/cache/pacman/workstation.db ]] || usb_die "Official package database is missing."
  usb_ok "Official offline package cache passed verification."
else
  usb_warn "No offline official package cache is present; offline boot/configuration still works, but a full offline installation does not."
fi

if [[ -d $LAYOUT/cache/aur ]]; then
  usb_verify_directory_manifest "$LAYOUT/cache/aur" \
    || usb_die "AUR package-cache checksum verification failed."
  [[ -s $LAYOUT/cache/aur/workstation-aur.db ]] || usb_die "AUR package database is missing."
  usb_ok "AUR offline package cache passed verification."
else
  usb_warn "No offline AUR package cache is present."
fi

active=$(usb_read_active_slot "$USB_ROOT")
usb_ok "USB verification completed. Active slot for the next boot: $active."
