#!/usr/bin/env bash

SECURITY_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
SECURITY_CONFIG="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
CRYPTTAB_INITRAMFS_PATH="${CRYPTTAB_INITRAMFS_PATH:-/etc/crypttab.initramfs}"

# shellcheck source=../lib/common.sh
source "$SECURITY_ROOT/scripts/lib/common.sh"
# shellcheck source=../lib/config.sh
source "$SECURITY_ROOT/scripts/lib/config.sh"

load_runtime_security() {
  require_root
  [[ -r $SECURITY_CONFIG ]] || die "Configuration not found: $SECURITY_CONFIG"
  [[ -r /etc/arch-installer/install.env ]] || die "Installer metadata is missing: /etc/arch-installer/install.env"
  load_config "$SECURITY_CONFIG"
  validate_config runtime
  # shellcheck source=/dev/null
  source /etc/arch-installer/install.env
}

resolve_luks_device() {
  local by_uuid="/dev/disk/by-uuid/$LUKS_UUID"
  if [[ -b $by_uuid ]]; then
    readlink -f "$by_uuid"
  elif [[ -n ${ROOT_PART:-} && -b $ROOT_PART ]]; then
    readlink -f "$ROOT_PART"
  else
    die "Could not resolve the LUKS device for UUID $LUKS_UUID."
  fi
}

secure_boot_keys_present() {
  local relative
  for relative in \
    PK/PK.key PK/PK.pem \
    KEK/KEK.key KEK/KEK.pem \
    db/db.key db/db.pem; do
    [[ -r /var/lib/sbctl/keys/$relative ]] || return 1
  done
}

secure_boot_key_material_exists() {
  [[ -d /var/lib/sbctl ]] \
    && find /var/lib/sbctl -mindepth 1 -maxdepth 4 -type f -print -quit 2>/dev/null | grep -q .
}

tpm_token_present() {
  local luks_device=${1:-}
  [[ -n $luks_device ]] || luks_device=$(resolve_luks_device)
  cryptsetup luksDump "$luks_device" 2>/dev/null | grep -q 'systemd-tpm2'
}

tpm_unlock_configured() {
  [[ -r $CRYPTTAB_INITRAMFS_PATH ]] || return 1
  awk -v expected_uuid="UUID=$LUKS_UUID" '
    $1 == "cryptroot" && $2 == expected_uuid && $3 == "none" {
      count = split($4, options, ",")
      for (i = 1; i <= count; i++) {
        if (options[i] == "tpm2-device=auto") found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$CRYPTTAB_INITRAMFS_PATH"
}

write_tpm_crypttab() {
  local options='tpm2-device=auto'
  if bool_true "$ENABLE_SSD_TRIM"; then
    options+=',discard'
  fi
  cat > "$CRYPTTAB_INITRAMFS_PATH" <<EOF
cryptroot UUID=$LUKS_UUID none $options
EOF
  chmod 0600 "$CRYPTTAB_INITRAMFS_PATH"
}

write_passphrase_crypttab() {
  local options='luks'
  if bool_true "$ENABLE_SSD_TRIM"; then
    options+=',discard'
  fi
  cat > "$CRYPTTAB_INITRAMFS_PATH" <<EOF
cryptroot UUID=$LUKS_UUID none $options
EOF
  chmod 0600 "$CRYPTTAB_INITRAMFS_PATH"
}

install_ukify_signing_config() {
  secure_boot_keys_present || die "sbctl signing keys are not present."
  install -d -m 0755 /etc/kernel
  cat > /etc/kernel/uki.conf <<'EOF'
[UKI]
SecureBootPrivateKey=/var/lib/sbctl/keys/db/db.key
SecureBootCertificate=/var/lib/sbctl/keys/db/db.pem
EOF
  chmod 0600 /etc/kernel/uki.conf
}

verify_expected_ukis() {
  local kernel
  local -a kernel_list
  read -r -a kernel_list <<< "$KERNELS"
  for kernel in "${kernel_list[@]}"; do
    [[ -s /efi/EFI/Linux/arch-${kernel}.efi ]] \
      || die "Expected UKI is missing: /efi/EFI/Linux/arch-${kernel}.efi"
  done
}

sign_boot_assets() {
  require_commands find sbctl sort
  secure_boot_keys_present || die "sbctl signing keys are not present."
  [[ -d /efi/EFI ]] || die "EFI System Partition is not mounted at /efi."

  local asset count=0
  while IFS= read -r -d '' asset; do
    info "Signing and registering $asset"
    ESP_PATH=/efi sbctl sign --save "$asset"
    ((count += 1))
  done < <(find /efi/EFI -type f -iname '*.efi' -print0 | sort -z)

  ((count > 0)) || die "No EFI binaries were found under /efi/EFI."
  ESP_PATH=/efi sbctl sign-all
  ESP_PATH=/efi sbctl verify \
    || die "At least one EFI binary does not verify against the sbctl db key."
}

rebuild_and_sign_ukis() {
  require_commands mkinitcpio

  local sign_after=false
  if bool_true "${ENABLE_SECURE_BOOT:-false}" || secure_boot_enabled; then
    secure_boot_keys_present || die "Secure Boot signing keys are missing; refusing to rebuild UKIs."
    install_ukify_signing_config
    sign_after=true
  elif secure_boot_keys_present; then
    install_ukify_signing_config
    sign_after=true
  fi

  mkinitcpio -P
  verify_expected_ukis
  if bool_true "$sign_after"; then
    sign_boot_assets
  fi
}

write_state_marker() {
  local marker=$1
  install -d -m 0755 "$STATE_DIR"
  printf '%s\n' "$(date --iso-8601=seconds)" > "$STATE_DIR/$marker"
  chmod 0644 "$STATE_DIR/$marker"
}
