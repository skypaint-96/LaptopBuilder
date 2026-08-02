#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_runtime_security
require_commands cryptsetup mkinitcpio sbctl systemd-cryptenroll
if bool_true "$ENABLE_SECURE_BOOT" || secure_boot_enabled; then
  secure_boot_keys_present || die "Secure Boot signing keys are missing; refusing to alter TPM enrollment."
fi
luks_device=$(resolve_luks_device)

warn "Before TPM removal, prove that an ordinary LUKS passphrase or recovery key works."
read_secret_into TPM_REMOVE_PASSPHRASE "" "Existing LUKS passphrase or recovery key" false
trap 'unset TPM_REMOVE_PASSPHRASE' EXIT
if ! printf '%s' "$TPM_REMOVE_PASSPHRASE" | \
  cryptsetup open --type luks2 --test-passphrase --key-file - "$luks_device"; then
  die "The supplied non-TPM LUKS credential did not unlock the volume; TPM removal was cancelled."
fi
unset TPM_REMOVE_PASSPHRASE
trap - EXIT

warn "Removing all systemd TPM2 enrollments from $luks_device."
systemd-cryptenroll --wipe-slot=tpm2 "$luks_device"
crypt_options="luks"
if bool_true "$ENABLE_SSD_TRIM"; then
  crypt_options+=",discard"
fi
cat > /etc/crypttab.initramfs <<EOF
cryptroot UUID=$LUKS_UUID none $crypt_options
EOF
chmod 0600 /etc/crypttab.initramfs
rebuild_and_sign_ukis
success "TPM2 enrollment removed. Boot now uses a LUKS passphrase."
