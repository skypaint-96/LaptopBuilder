#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  README.md LICENSE VERSION install.sh archctl
  config/install.conf.example config/usb.conf.example profiles/t480.conf
  scripts/install/01-preflight.sh
  scripts/install/10-disk.sh
  scripts/install/20-base.sh
  scripts/install/chroot-configure.sh
  scripts/security/secure-boot.sh
  scripts/security/tpm-enroll.sh
  scripts/security/tpm-remove.sh
  scripts/security/recovery-key.sh
  scripts/security/verify.sh
  tests/check-arch-packages.sh
  tests/check-aur-packages.sh tests/test-usb.sh
  tests/test-source-copy.sh
  ansible/site.yml
  docs/INSTALLATION.md docs/ARCHITECTURE.md docs/SECURITY.md docs/RECOVERY.md
  docs/CUSTOMISING.md docs/PACKAGES.md docs/REFERENCES.md docs/TESTING.md docs/USB-INSTALLER.md
  usb/create-usb.sh usb/start.sh usb/live-installer.sh usb/refresh-arch.sh
  usb/refresh-packages.sh usb/verify-usb.sh usb/lib/usb-common.sh usb/grub/grub.cfg
  scripts/lib/packages.sh scripts/lib/install-source.sh
)

for path in "${required[@]}"; do
  [[ -e $path ]] || { echo "Missing required path: $path" >&2; exit 1; }
done

for path in install.sh archctl scripts/*.sh scripts/install/*.sh scripts/lib/*.sh scripts/security/*.sh tests/*.sh usb/*.sh usb/lib/*.sh; do
  [[ -x $path ]] || { echo "Expected executable bit: $path" >&2; exit 1; }
done

[[ ! -e config/install.conf ]] || { echo 'config/install.conf must not be committed.' >&2; exit 1; }
[[ ! -e config/secrets.conf ]] || { echo 'config/secrets.conf must not be committed.' >&2; exit 1; }

if grep -RIl $'\r' --exclude-dir=.git . | grep -q .; then
  echo 'CRLF line endings detected:' >&2
  grep -RIl $'\r' --exclude-dir=.git . >&2
  exit 1
fi

if grep -RIE --exclude-dir=.git --exclude='check-repo.sh' \
  'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|password[[:space:]]*=[[:space:]]*[^"[:space:]]+' .; then
  echo 'Possible committed secret material detected.' >&2
  exit 1
fi

grep -q 'ERASE \$DISK' scripts/install/01-preflight.sh
grep -q 'ENROLL SECURE BOOT KEYS' scripts/security/secure-boot.sh
grep -q -- '--wipe-slot=tpm2' scripts/security/tpm-enroll.sh
grep -q 'INSTALL_LUKS_PASSPHRASE' install.sh
grep -q 'Secure Boot is not active' scripts/security/tpm-enroll.sh
grep -q 'Secure Boot signing keys are missing; refusing to rebuild UKIs' scripts/security/common.sh
grep -q 'GPU_VENDOR=intel or amd' scripts/lib/config.sh
grep -q 'config/install.conf' scripts/install/20-base.sh
grep -q 'BUILD PARU' scripts/install-aur.sh
grep -q 'readlink -f' archctl
grep -q 'sign_boot_assets=false' scripts/update.sh
grep -q 'Runtime safety overrides' scripts/install/20-base.sh
grep -q '/etc/kernel/uki.conf is missing' scripts/update.sh
grep -q 'SNAPPER_CONFIGS' ansible/roles/snapshots/tasks/main.yml
grep -q 'TARGET_MOUNTED_BY_INSTALLER' scripts/lib/common.sh
grep -q -- '--test-passphrase' scripts/security/tpm-remove.sh
grep -q -- "--exclude='.git'" scripts/install/20-base.sh
grep -Fq -- "--loader '\\EFI\\systemd\\systemd-bootx64.efi'" scripts/install/20-base.sh
grep -q '/etc/pacman.d/hooks/90-systemd-boot-update.hook' scripts/install/chroot-configure.sh
if grep -q '/etc/pacman.d/hooks/95-systemd-boot-update.hook' scripts/install/chroot-configure.sh; then
  echo 'The systemd-boot hook must sort before the sbctl signing hook.' >&2
  exit 1
fi
grep -q 'swapon --show=NAME' scripts/install/01-preflight.sh
grep -q '/efi is not mounted; refusing to update kernels or boot assets' scripts/update.sh
grep -q 'Secure Boot is enabled or expected' scripts/update.sh
grep -q '/efi is not mounted; refusing to alter a workstation with missing boot assets' scripts/provision.sh
grep -q 'systemd-ukify sbsigntools sbctl tpm2-tools tpm2-tss' scripts/lib/packages.sh
grep -q 'ERASE \$DISK' usb/create-usb.sh
grep -q 'previous.tar.gz' usb/start.sh
grep -q 'MASON_REPO_COMMIT' usb/start.sh
grep -q 'usb_write_active_slot' usb/refresh-arch.sh
grep -q 'validate_staged_cache_pair' usb/refresh-packages.sh
grep -q 'validate_offline_source' scripts/lib/install-source.sh

echo 'Repository structure and safety assertions passed.'
