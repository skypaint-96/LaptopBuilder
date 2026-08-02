#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_runtime_security
require_commands awk cryptsetup mkinitcpio sbctl systemd-cryptenroll tpm2_getcap

bool_true "$ENABLE_TPM" || die "ENABLE_TPM is false in $SECURITY_CONFIG."
secure_boot_enabled || die "Secure Boot is not active. Enable it and boot the signed Arch UKI before TPM enrollment."
secure_boot_keys_present || die "sbctl signing keys are missing; refusing TPM enrollment because the rebuilt UKI could not be signed."
[[ -e /sys/class/tpm/tpm0 ]] || die "No TPM2 device is visible. Enable the security chip in firmware."

luks_device=$(resolve_luks_device)
[[ $(cryptsetup luksDump "$luks_device" | awk '/^Version:/ {print $2; exit}') == 2 ]] || die "$luks_device is not LUKS2."

info "TPM capabilities are visible. Enrolling against PCRs: $TPM_PCRS"
tpm2_getcap properties-fixed >/dev/null

args=(
  --wipe-slot=tpm2
  --tpm2-device=auto
  "--tpm2-pcrs=$TPM_PCRS"
)
if bool_true "$TPM_WITH_PIN"; then
  args+=(--tpm2-with-pin=yes)
else
  args+=(--tpm2-with-pin=no)
fi

warn "You will be asked for an existing LUKS passphrase."
if bool_true "$TPM_WITH_PIN"; then
  warn "You will also set a TPM PIN. Repeated wrong PINs can trigger TPM lockout."
fi
systemd-cryptenroll "${args[@]}" "$luks_device"

crypt_options="tpm2-device=auto"
if bool_true "$ENABLE_SSD_TRIM"; then
  crypt_options+=",discard"
fi
cat > /etc/crypttab.initramfs <<EOF
cryptroot UUID=$LUKS_UUID none $crypt_options
EOF
chmod 0600 /etc/crypttab.initramfs
rebuild_and_sign_ukis

success "TPM2 unlock was enrolled; the ordinary LUKS passphrase was retained."
echo "Reboot once and test both TPM unlock and passphrase fallback before relying on this configuration."
