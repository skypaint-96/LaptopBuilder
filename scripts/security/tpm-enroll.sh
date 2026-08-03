#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

FORCE=false
PENDING_CREDENTIAL_DIR=/var/lib/arch-workstation/pending-credentials
while (($#)); do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      echo 'Usage: archctl tpm-enroll [--force]'
      exit 0
      ;;
    *)
      die "Unknown tpm-enroll option: $1"
      ;;
  esac
done

load_runtime_security
require_commands awk cryptsetup findmnt mkinitcpio sbctl systemd-cryptenroll tpm2_getcap

bool_true "$ENABLE_TPM" || die "ENABLE_TPM is false in $SECURITY_CONFIG."
secure_boot_enabled || die "Secure Boot is not active. Enable it and boot the signed Arch UKI before TPM enrollment."
secure_boot_keys_present || die "sbctl signing keys are missing; refusing TPM enrollment because rebuilt UKIs could not be signed."
findmnt -rn /efi >/dev/null || die "The EFI System Partition is not mounted at /efi."
ESP_PATH=/efi sbctl verify >/dev/null \
  || die "EFI verification failed. Repair signing with 'archctl secure-boot --sign-only' before TPM enrollment."
[[ -e /sys/class/tpm/tpm0 ]] || die "No TPM2 device is visible. Enable the security chip in firmware."

luks_device=$(resolve_luks_device)
[[ $(cryptsetup luksDump "$luks_device" | awk '/^Version:/ {print $2; exit}') == 2 ]] || die "$luks_device is not LUKS2."

pending_credentials_available() {
  [[ -s $PENDING_CREDENTIAL_DIR/luks-passphrase ]] || return 1
  if bool_true "$TPM_WITH_PIN"; then
    [[ -s $PENDING_CREDENTIAL_DIR/tpm2-pin ]] || return 1
  fi
}

remove_pending_credentials() {
  local credential
  for credential in "$PENDING_CREDENTIAL_DIR/luks-passphrase" "$PENDING_CREDENTIAL_DIR/tpm2-pin"; do
    [[ -e $credential ]] || continue
    if command -v shred >/dev/null 2>&1; then
      shred --force --iterations=1 --zero --remove "$credential" 2>/dev/null || rm -f "$credential"
    else
      rm -f "$credential"
    fi
  done
  rm -f "$PENDING_CREDENTIAL_DIR/README"
  sync
}

enroll_with_staged_credentials() {
  require_commands bash systemd-run
  local unlock_file="$PENDING_CREDENTIAL_DIR/luks-passphrase"
  local pin_file="$PENDING_CREDENTIAL_DIR/tpm2-pin"
  local -a properties=(
    --property="LoadCredential=cryptenroll.passphrase:$unlock_file"
  )
  if bool_true "$TPM_WITH_PIN"; then
    properties+=(
      --property="LoadCredential=cryptenroll.new-tpm2-pin:$pin_file"
      --property="LoadCredential=cryptenroll.tpm2-pin:$pin_file"
    )
  fi

  info 'Using credentials staged inside the encrypted, non-snapshotted credentials subvolume.'
  systemd-run --quiet --wait --pipe --collect --service-type=exec \
    "${properties[@]}" \
    /usr/bin/bash -c '
      set -Eeuo pipefail
      unlock_file="$CREDENTIALS_DIRECTORY/cryptenroll.passphrase"
      exec /usr/bin/systemd-cryptenroll --unlock-key-file="$unlock_file" "$@"
    ' arch-workstation-cryptenroll "${args[@]}" "$luks_device"
}

if tpm_token_present "$luks_device" && ! bool_true "$FORCE"; then
  info "A systemd TPM2 token already exists; repairing boot configuration and signatures without replacing it."
else
  info "TPM capabilities are visible. Enrolling against PCRs: $TPM_PCRS"
  tpm2_getcap properties-fixed >/dev/null

  declare -a args=(
    --wipe-slot=tpm2
    --tpm2-device=auto
    "--tpm2-pcrs=$TPM_PCRS"
  )
  if bool_true "$TPM_WITH_PIN"; then
    args+=(--tpm2-with-pin=yes)
  else
    args+=(--tpm2-with-pin=no)
  fi

  if pending_credentials_available; then
    enroll_with_staged_credentials
  else
    warn "Enter the retained LUKS passphrase when requested."
    if bool_true "$TPM_WITH_PIN"; then
      warn "Choose a TPM PIN you can enter daily; six or more digits is recommended. Repeated wrong PINs can trigger TPM lockout."
    fi
    systemd-cryptenroll "${args[@]}" "$luks_device"
  fi
fi

write_tpm_crypttab
rebuild_and_sign_ukis

tpm_token_present "$luks_device" || die "No systemd-tpm2 token is visible after TPM setup."
tpm_unlock_configured || die "The initramfs crypttab does not request TPM2 unlocking after TPM setup."
write_state_marker tpm-enrolled
remove_pending_credentials
success "TPM2 unlock is enrolled and the signed initramfs is configured; the ordinary LUKS passphrase remains available for recovery."
