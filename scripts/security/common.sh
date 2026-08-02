#!/usr/bin/env bash

SECURITY_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
SECURITY_CONFIG="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"

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
  [[ -r /var/lib/sbctl/keys/db/db.key && -r /var/lib/sbctl/keys/db/db.pem ]]
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

sign_boot_assets() {
  require_commands sbctl find
  secure_boot_keys_present || die "sbctl signing keys are not present."
  [[ -d /efi/EFI ]] || die "EFI System Partition is not mounted at /efi."

  local asset count=0
  while IFS= read -r -d '' asset; do
    sbctl sign --save "$asset"
    ((count += 1))
  done < <(find /efi/EFI -type f -iname '*.efi' -print0)
  ((count > 0)) || die "No EFI binaries were found under /efi/EFI."
  sbctl verify
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
  if bool_true "$sign_after"; then
    sign_boot_assets
  fi
}
