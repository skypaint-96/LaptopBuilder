#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_runtime_security
require_commands bootctl find findmnt mkinitcpio sbctl

bool_true "$ENABLE_SECURE_BOOT" || die "ENABLE_SECURE_BOOT is false in $SECURITY_CONFIG."
[[ -d /sys/firmware/efi/efivars ]] || die "The running system was not booted in UEFI mode."
findmnt -rn /efi >/dev/null || die "The EFI System Partition is not mounted at /efi."

info "Current Secure Boot state:"
sbctl status || true

if ! setup_mode_enabled && ! secure_boot_keys_present; then
  die "Firmware is not in Setup Mode and no existing sbctl keys are available. Clear Secure Boot keys in firmware first."
fi

if setup_mode_enabled; then
  if ! secure_boot_keys_present; then
    info "Creating local Secure Boot owner keys."
    sbctl create-keys
  fi
  expected="ENROLL SECURE BOOT KEYS"
  if bool_true "$NONINTERACTIVE"; then
    [[ $SECURE_BOOT_CONFIRMATION == "$expected" ]] || die "Unattended enrollment requires SECURE_BOOT_CONFIRMATION=\"$expected\"."
  else
    warn "This writes Platform, KEK, and db keys to UEFI firmware."
    warn "The script never bypasses sbctl option-ROM or immutable-variable safety checks."
    read -r -p "Type '$expected' to continue: " response
    [[ $response == "$expected" ]] || die "Secure Boot key enrollment was not confirmed."
  fi

  enroll_args=(enroll-keys)
  if bool_true "$SBCTL_ENROLL_MICROSOFT"; then
    enroll_args+=(--microsoft)
  fi
  sbctl "${enroll_args[@]}"
  success "Owner keys were enrolled in firmware."
else
  warn "Firmware is not in Setup Mode; key enrollment was skipped."
  warn "This is expected on a repeat run after the owner keys have already been enrolled."
fi

info "Updating systemd-boot and rebuilding UKIs."
bootctl --esp-path=/efi update
install_ukify_signing_config
mkinitcpio -P
sign_boot_assets

cat <<EOF

Secure Boot assets are signed and tracked by sbctl.

Next:
  1. Reboot into firmware setup.
  2. Enable Secure Boot without restoring factory keys.
  3. Boot Arch and confirm Secure Boot with: sudo sbctl status
  4. Only then enroll TPM unlocking: sudo archctl tpm-enroll

Keep the LUKS passphrase. It remains the recovery path.
EOF
