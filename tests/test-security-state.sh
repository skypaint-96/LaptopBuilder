#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
export CRYPTTAB_INITRAMFS_PATH="$TEMP_DIR/crypttab.initramfs"

# shellcheck source=../scripts/security/common.sh
source "$ROOT/scripts/security/common.sh"

LUKS_UUID='11111111-2222-3333-4444-555555555555'
ENABLE_SSD_TRIM=true

! tpm_unlock_configured
write_tpm_crypttab
tpm_unlock_configured
grep -qx "cryptroot UUID=$LUKS_UUID none tpm2-device=auto,discard" "$CRYPTTAB_INITRAMFS_PATH"

write_passphrase_crypttab
! tpm_unlock_configured
grep -qx "cryptroot UUID=$LUKS_UUID none luks,discard" "$CRYPTTAB_INITRAMFS_PATH"

cat > "$CRYPTTAB_INITRAMFS_PATH" <<EOF_BAD
other UUID=$LUKS_UUID none tpm2-device=auto
cryptroot UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee none tpm2-device=auto
EOF_BAD
! tpm_unlock_configured

echo 'TPM crypttab state tests passed.'
