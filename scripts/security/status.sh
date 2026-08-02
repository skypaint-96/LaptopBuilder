#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

STAGE_ONLY=false
while (($#)); do
  case "$1" in
    --stage)
      STAGE_ONLY=true
      shift
      ;;
    -h|--help)
      echo 'Usage: archctl status [--stage]'
      exit 0
      ;;
    *)
      die "Unknown status option: $1"
      ;;
  esac
done

load_runtime_security
require_commands cryptsetup findmnt sbctl

provisioned=false
keys_present=false
assets_signed=false
secure_active=false
setup_active=false
tpm_present=false
tpm_configured=false
tpm_ready=false

[[ -f $STATE_DIR/provisioned ]] && provisioned=true
secure_boot_keys_present && keys_present=true
secure_boot_enabled && secure_active=true
setup_mode_enabled && setup_active=true

if bool_true "$keys_present" && findmnt -rn /efi >/dev/null 2>&1; then
  if ESP_PATH=/efi sbctl verify >/dev/null 2>&1; then
    assets_signed=true
  fi
fi

if bool_true "$ENABLE_TPM"; then
  luks_device=$(resolve_luks_device)
  tpm_token_present "$luks_device" && tpm_present=true
  tpm_unlock_configured && tpm_configured=true
  if bool_true "$tpm_present" && bool_true "$tpm_configured"; then
    tpm_ready=true
  fi
fi

stage=complete
if bool_true "$ENABLE_SECURE_BOOT" && bool_true "$setup_active"; then
  # Setup Mode means the firmware does not currently enforce an enrolled
  # Platform Key. Re-run owner-key preparation even when local key files
  # survived an interrupted enrollment or a later firmware key clear.
  stage=prepare-secure-boot
elif bool_true "$ENABLE_SECURE_BOOT" && ! bool_true "$keys_present"; then
  stage=firmware-setup-mode
elif ! bool_true "$provisioned"; then
  stage=provision
elif bool_true "$ENABLE_SECURE_BOOT" && ! bool_true "$assets_signed"; then
  stage=prepare-secure-boot
elif bool_true "$ENABLE_SECURE_BOOT" && ! bool_true "$secure_active"; then
  stage=enable-secure-boot
elif bool_true "$ENABLE_TPM" && ! bool_true "$tpm_ready"; then
  stage=enroll-tpm
fi

if bool_true "$STAGE_ONLY"; then
  printf '%s\n' "$stage"
  exit 0
fi

print_state() {
  local label=$1 value=$2
  if bool_true "$value"; then
    printf '[ OK ] %s\n' "$label"
  else
    printf '[ .. ] %s\n' "$label"
  fi
}

print_state 'Provisioning completed' "$provisioned"
if bool_true "$ENABLE_SECURE_BOOT"; then
  if bool_true "$keys_present"; then
    if bool_true "$setup_active"; then
      print_state 'Firmware has left Secure Boot Setup Mode' false
    else
      print_state 'Firmware has left Secure Boot Setup Mode' true
    fi
  else
    print_state 'Firmware is in Secure Boot Setup Mode' "$setup_active"
  fi
  print_state 'Local sbctl owner keys exist' "$keys_present"
  print_state 'Every EFI binary verifies against the db key' "$assets_signed"
  print_state 'Secure Boot is active' "$secure_active"
fi
if bool_true "$ENABLE_TPM"; then
  print_state 'LUKS2 contains a systemd TPM2 token' "$tpm_present"
  print_state 'Initramfs crypttab requests TPM2 unlock' "$tpm_configured"
fi

printf '\nCurrent stage: %s\n' "$stage"
case "$stage" in
  provision)
    echo 'Next: run archctl finish to apply packages and configuration.'
    ;;
  firmware-setup-mode)
    echo 'Next: reboot to firmware, disable Secure Boot, clear enrolled Secure Boot keys, then run archctl finish.'
    ;;
  prepare-secure-boot)
    echo 'Next: run archctl finish to enrol/sign the Secure Boot chain.'
    ;;
  enable-secure-boot)
    echo 'Next: enable Secure Boot in firmware without clearing/restoring keys, boot Arch, then run archctl finish.'
    ;;
  enroll-tpm)
    echo 'Next: run archctl finish and enter the retained LUKS passphrase plus a daily TPM PIN.'
    ;;
  complete)
    echo 'Next: no setup action is pending; run archctl verify for the strict final audit.'
    ;;
esac
