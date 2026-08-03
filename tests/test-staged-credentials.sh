#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -q 'subvolume create.*@credentials' "$ROOT/scripts/install/10-disk.sh"
grep -q 'subvol=@credentials' "$ROOT/scripts/install/20-base.sh"
grep -q 'pending-credentials' "$ROOT/scripts/install/20-base.sh"
grep -q 'LoadCredential=cryptenroll.passphrase' "$ROOT/scripts/security/tpm-enroll.sh"
grep -q 'cryptenroll.new-tpm2-pin' "$ROOT/scripts/security/tpm-enroll.sh"
grep -q 'remove_pending_credentials' "$ROOT/scripts/security/tpm-enroll.sh"
grep -q 'TPM_PIN_FILE' "$ROOT/install.sh"
grep -q 'pending_credentials' "$ROOT/scripts/security/status.sh"
grep -q 'pending_credentials_removed' "$ROOT/scripts/security/verify.sh"

echo 'Staged first-boot credential assertions passed.'
