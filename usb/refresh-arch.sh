#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/usb-common.sh
source "$REPO_ROOT/usb/lib/usb-common.sh"

USB_ROOT="${MASON_USB_ROOT:-}"
IF_NEWER=false

usage() {
  cat <<'USAGE'
Usage: sudo ./usb/refresh-arch.sh [--usb-root PATH] [--if-newer]

Downloads and verifies the current official Arch ISO, extracts it into the
non-running A/B slot, verifies that slot, then selects it for the next boot.
The running slot is never overwritten. Exit status 10 means a new slot was
staged and a reboot is required to use it.
USAGE
}

while (($#)); do
  case "$1" in
    --usb-root) [[ $# -ge 2 ]] || usb_die "--usb-root requires a path"; USB_ROOT=$2; shift 2 ;;
    --if-newer) IF_NEWER=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usb_die "Unknown option: $1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || usb_die "Arch cache refresh must run as root."
[[ -n $USB_ROOT ]] || USB_ROOT=$(usb_find_root) || usb_die "Installer USB not found."
usb_verify_layout "$USB_ROOT" || usb_die "Invalid installer USB layout: $USB_ROOT"
LAYOUT=$(usb_layout_dir "$USB_ROOT")
usb_load_config "$LAYOUT/config/usb.conf"
usb_require_commands awk bsdtar curl pacman-key sha256sum
usb_remount_rw "$USB_ROOT"
usb_recover_interrupted_updates "$USB_ROOT"
usb_network_available || usb_die "An internet connection is required to refresh the Arch cache."

current_slot=$(usb_current_arch_slot || usb_read_active_slot "$USB_ROOT")
inactive_slot=$(usb_other_slot "$current_slot")
active_slot=$(usb_read_active_slot "$USB_ROOT")
current_version=$(tr -d '\r\n' < "$USB_ROOT/arch-$current_slot/version" 2>/dev/null || true)
inactive_version=$(tr -d '\r\n' < "$USB_ROOT/arch-$inactive_slot/version" 2>/dev/null || true)
remote_version=$(curl -fL --retry 3 "$ARCH_MIRROR/iso/latest/version" | tr -d '\r\n')
[[ -n $remote_version ]] || usb_die "The current Arch image version could not be determined."

if usb_bool_true "$IF_NEWER"; then
  if [[ $current_version == "$remote_version" ]]; then
    usb_write_active_slot "$USB_ROOT" "$current_slot"
    usb_ok "The running Arch slot is already current ($remote_version)."
    exit 0
  fi
  if [[ $inactive_version == "$remote_version" && $active_slot == "$inactive_slot" ]]; then
    usb_ok "Arch $remote_version is already staged in slot $inactive_slot for the next boot."
    exit 0
  fi
fi

DOWNLOADS="$LAYOUT/cache/downloads"
mkdir -p "$DOWNLOADS"
ISO="$DOWNLOADS/archlinux-x86_64.iso"
SIG="$ISO.sig"
SUMS="$DOWNLOADS/sha256sums.txt"

usb_info "Downloading Arch $remote_version for inactive slot $inactive_slot."
curl -fL --retry 3 --continue-at - "$ARCH_MIRROR/iso/latest/archlinux-x86_64.iso" -o "$ISO.part"
mv -f "$ISO.part" "$ISO"
curl -fL --retry 3 "$ARCH_MIRROR/iso/latest/archlinux-x86_64.iso.sig" -o "$SIG"
curl -fL --retry 3 "https://archlinux.org/iso/latest/sha256sums.txt" -o "$SUMS"

expected_hash=$(awk '$2 == "archlinux-x86_64.iso" {print $1}' "$SUMS" | head -n 1)
actual_hash=$(sha256sum "$ISO" | awk '{print $1}')
[[ -n $expected_hash && $actual_hash == "$expected_hash" ]] \
  || usb_die "Arch ISO SHA-256 verification failed."
pacman-key -v "$SIG" || usb_die "Arch ISO PGP signature verification failed."
usb_ok "Arch ISO PGP signature and SHA-256 checksum verified."

STAGE_PARENT="$USB_ROOT/.arch-refresh-$inactive_slot"
NEW="$USB_ROOT/arch-$inactive_slot.new"
OLD="$USB_ROOT/arch-$inactive_slot.old"
rm -rf "$STAGE_PARENT" "$NEW"
mkdir -p "$STAGE_PARENT"
bsdtar -xf "$ISO" -C "$STAGE_PARENT" arch
mv "$STAGE_PARENT/arch" "$NEW"
rmdir "$STAGE_PARENT"
usb_verify_arch_slot "$USB_ROOT" "$inactive_slot.new" \
  || { rm -rf "$NEW"; usb_die "The newly extracted Arch slot failed validation."; }
sync

rm -rf "$OLD"
if [[ -e $USB_ROOT/arch-$inactive_slot ]]; then
  mv "$USB_ROOT/arch-$inactive_slot" "$OLD"
fi
if ! mv "$NEW" "$USB_ROOT/arch-$inactive_slot"; then
  [[ ! -e $OLD ]] || mv "$OLD" "$USB_ROOT/arch-$inactive_slot"
  usb_die "The refreshed slot could not be activated; the old slot was restored."
fi
if ! usb_verify_arch_slot "$USB_ROOT" "$inactive_slot"; then
  rm -rf "$USB_ROOT/arch-$inactive_slot"
  [[ ! -e $OLD ]] || mv "$OLD" "$USB_ROOT/arch-$inactive_slot"
  usb_die "The activated slot failed verification; the old slot was restored."
fi
sync
rm -rf "$OLD"

usb_write_active_slot "$USB_ROOT" "$inactive_slot"
printf '%s\n' "$inactive_slot" > "$LAYOUT/state/last-arch-update-slot"
printf '%s\n' "$remote_version" > "$LAYOUT/state/last-arch-version"
printf '%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$LAYOUT/state/last-arch-refresh"

if ! usb_bool_true "$KEEP_DOWNLOADED_ISO"; then
  rm -f "$ISO" "$SIG" "$SUMS"
fi
sync
usb_ok "Arch $remote_version is cached in slot $inactive_slot and will boot next; slot $current_slot remains the recovery copy."
exit 10
