#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ASSUME_YES=false
SIGN_ONLY=false

usage() {
  cat <<'EOF'
Usage: archctl secure-boot [--yes] [--sign-only]

--yes        Skip the owner-key enrollment confirmation.
--sign-only  Rebuild and sign boot assets without attempting key enrollment.
EOF
}

while (($#)); do
  case "$1" in
    --yes)
      ASSUME_YES=true
      shift
      ;;
    --sign-only)
      SIGN_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown secure-boot option: $1"
      ;;
  esac
done

load_runtime_security
require_commands bootctl find findmnt mkinitcpio sbctl

bool_true "$ENABLE_SECURE_BOOT" || die "ENABLE_SECURE_BOOT is false in $SECURITY_CONFIG."
[[ -d /sys/firmware/efi/efivars ]] || die "The running system was not booted in UEFI mode."
findmnt -rn /efi >/dev/null || die "The EFI System Partition is not mounted at /efi."

info "Current Secure Boot state:"
ESP_PATH=/efi sbctl status || true

if bool_true "$SIGN_ONLY"; then
  secure_boot_keys_present || die "Cannot use --sign-only because no sbctl keys are available."
else
  if ! setup_mode_enabled && ! secure_boot_keys_present; then
    die "Firmware is not in Setup Mode and no local sbctl keys exist. Reboot to firmware, disable Secure Boot, and clear the enrolled Secure Boot keys first."
  fi

  if setup_mode_enabled; then
    if ! secure_boot_keys_present; then
      if secure_boot_key_material_exists; then
        incomplete_backup="/var/lib/sbctl.incomplete-$(date +%Y%m%d-%H%M%S)"
        warn "Local sbctl state is incomplete; preserving it at $incomplete_backup before generating a coherent key hierarchy."
        mv /var/lib/sbctl "$incomplete_backup"
      fi
      info "Creating local Secure Boot owner keys."
      sbctl create-keys
    fi

    if ! bool_true "$ASSUME_YES"; then
      warn "This will write Platform, KEK, and db owner keys to UEFI firmware."
      confirm "Enroll the generated Secure Boot keys now?" no \
        || die "Secure Boot key enrollment was cancelled."
    fi

    declare -a enroll_args=(enroll-keys)
    if bool_true "$SBCTL_ENROLL_MICROSOFT"; then
      enroll_args+=(--microsoft)
    fi
    sbctl "${enroll_args[@]}"
    success "Owner keys were enrolled in firmware."
  else
    info "Firmware is already outside Setup Mode; retaining the existing owner-key enrollment."
  fi
fi

info "Refreshing systemd-boot, rebuilding UKIs, and registering every EFI binary with sbctl."
bootctl --esp-path=/efi --no-variables install
install_ukify_signing_config
mkinitcpio -P
verify_expected_ukis
sign_boot_assets
write_state_marker secure-boot-prepared

if secure_boot_enabled; then
  write_state_marker secure-boot-active
  success "Secure Boot is active and every EFI binary verifies."
else
  cat <<'EOF'

Secure Boot keys and boot assets are ready.

Next unavoidable step:
  1. Reboot into firmware setup.
  2. Enable Secure Boot.
  3. Do not clear keys or restore factory keys.
  4. Boot Arch and run: archctl finish

Use `systemctl reboot --firmware-setup` to open firmware setup directly when supported.
EOF
fi
