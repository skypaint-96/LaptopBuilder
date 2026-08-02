#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  README.md LICENSE VERSION .shellcheckrc install.sh start.sh archctl upgrade-existing.sh
  config/install.conf.example
  scripts/finish.sh scripts/provision.sh scripts/install-aur.sh scripts/update.sh
  scripts/install/01-preflight.sh
  scripts/install/10-disk.sh
  scripts/install/20-base.sh
  scripts/install/chroot-configure.sh
  scripts/security/common.sh
  scripts/security/status.sh
  scripts/security/secure-boot.sh
  scripts/security/tpm-enroll.sh
  scripts/security/tpm-remove.sh
  scripts/security/recovery-key.sh
  scripts/security/verify.sh
  tests/check-arch-packages.sh
  tests/check-aur-packages.sh
  tests/test-source-copy.sh
  tests/test-upgrade-existing.sh
  tests/test-package-lists.sh
  tests/test-security-state.sh
  ansible/site.yml
  docs/INSTALLATION.md docs/ARCHITECTURE.md docs/SECURITY.md docs/RECOVERY.md
  docs/CUSTOMISING.md docs/PACKAGES.md docs/REFERENCES.md docs/TESTING.md
  docs/MIGRATION.md
)

for path in "${required[@]}"; do
  [[ -e $path ]] || { echo "Missing required path: $path" >&2; exit 1; }
done

for path in install.sh start.sh archctl upgrade-existing.sh scripts/*.sh scripts/install/*.sh scripts/lib/*.sh scripts/security/*.sh tests/*.sh; do
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
grep -q 'REQUIRE_SETUP_MODE_AT_INSTALL' scripts/install/01-preflight.sh
grep -q 'verify_live_package_resolution' scripts/install/01-preflight.sh
grep -q 'verify_aur_package_resolution' scripts/install/01-preflight.sh
grep -q 'prepare_target_secure_boot' install.sh
grep -q 'AUTO_PREPARE_SECURE_BOOT=true' config/install.conf.example
grep -q 'AUR_HELPER_PACKAGE="paru-bin"' config/install.conf.example
grep -q -- '--skipreview' scripts/install-aur.sh
grep -q 'sudo env ANSIBLE_CONFIG=' scripts/provision.sh
grep -q 'become: false' ansible/site.yml
grep -q 'archctl finish' scripts/install/chroot-configure.sh
grep -q 'first-boot workflow' scripts/finish.sh
grep -q 'firmware-setup-mode' scripts/security/status.sh
grep -q 'find /efi/EFI -type f' scripts/security/common.sh
grep -q 'sbctl sign --save' scripts/security/common.sh
grep -q 'bootctl --esp-path=/efi --no-variables install' scripts/security/secure-boot.sh
grep -q -- '--wipe-slot=tpm2' scripts/security/tpm-enroll.sh
grep -q 'Secure Boot is not active' scripts/security/tpm-enroll.sh
grep -q 'Secure Boot signing keys are missing; refusing to rebuild UKIs' scripts/security/common.sh
grep -q 'GPU_VENDOR=intel or amd' scripts/lib/config.sh
grep -q 'config/install.conf' scripts/install/20-base.sh
grep -q 'readlink -f' archctl
grep -q 'user_exec' archctl
grep -q 'sudo -u "\$SUDO_USER" -H' archctl
grep -q -- '--sign-only' scripts/update.sh
grep -q 'Runtime safety overrides' scripts/install/20-base.sh
grep -q 'content: |' ansible/roles/snapshots/tasks/main.yml
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
grep -q 'systemd-ukify sbsigntools sbctl tpm2-tools tpm2-tss' scripts/install/20-base.sh
grep -q 'archctl finish' upgrade-existing.sh
grep -q 'UPGRADE_COMMITTED' upgrade-existing.sh
grep -q 'CONFIG_CHANGED' upgrade-existing.sh
grep -q 'tpm_unlock_configured' scripts/security/status.sh
grep -q 'tpm_unlock_configured' scripts/security/verify.sh
grep -q 'PK/PK.key PK/PK.pem' scripts/security/common.sh
grep -q 'sbctl.incomplete-' scripts/security/secure-boot.sh
grep -q 'archctl finish' start.sh

if grep -q 'BUILD PARU' scripts/install-aur.sh; then
  echo 'The obsolete interactive Paru build phrase remains.' >&2
  exit 1
fi
if grep -q -- '--ask-become-pass' scripts/provision.sh ansible/ansible.cfg; then
  echo 'Ansible should use the single established sudo session, not ask-become-pass.' >&2
  exit 1
fi

echo 'Repository structure and safety assertions passed.'
