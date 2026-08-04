#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp=$(mktemp -d)
secret_probe="$ROOT/config/usb-secrets.json"
bundle_probe="$ROOT/local-upgrade-probe.gpg"
cleanup() {
  rm -f "$secret_probe" "$bundle_probe"
  rm -rf "$temp"
}
trap cleanup EXIT
printf '%s\n' '{"user_password":"example-upgrade-only"}' > "$secret_probe"
printf '%s\n' 'encrypted-upgrade-probe' > "$bundle_probe"
chmod 0600 "$secret_probe" "$bundle_probe"

target="$temp/opt/arch-workstation"
config="$temp/etc/arch-installer/install.conf"
backup="$temp/backups"
bin="$temp/bin"
state="$temp/state"
mkdir -p "$target" "$(dirname "$config")"
printf 'old automation\n' > "$target/OLD_VERSION"
cat > "$config" <<'CONFIG'
DISK="/dev/test"
AUR_NONINTERACTIVE=false
PROVISION_NONINTERACTIVE=false
CONFIG

ARCH_WORKSTATION_TARGET="$target" \
ARCH_WORKSTATION_CONFIG="$config" \
ARCH_WORKSTATION_BACKUP_DIR="$backup" \
ARCH_WORKSTATION_BIN_DIR="$bin" \
ARCH_WORKSTATION_STATE_DIR="$state" \
ARCH_WORKSTATION_CONFIG_GROUP=root \
  "$ROOT/upgrade-existing.sh"

[[ -r $target/VERSION ]] || { echo 'New repository was not installed.' >&2; exit 1; }
[[ ! -e $target/OLD_VERSION ]] || { echo 'Old repository content survived replacement.' >&2; exit 1; }
[[ ! -e $target/config/usb-secrets.json ]] || { echo 'Plaintext USB secret input was copied during upgrade.' >&2; exit 1; }
[[ ! -e $target/local-upgrade-probe.gpg ]] || { echo 'Encrypted bundle artefact was copied during upgrade.' >&2; exit 1; }
[[ -L $target/config/install.conf ]] || { echo 'Installed configuration symlink is missing.' >&2; exit 1; }
[[ $(readlink "$target/config/install.conf") == "$config" ]] || { echo 'Configuration symlink points to the wrong path.' >&2; exit 1; }
grep -qx 'DISK="/dev/test"' "$config"
grep -qx 'AUR_HELPER_PACKAGE="paru"' "$config"
grep -qx 'AUR_NONINTERACTIVE=true' "$config"
grep -qx 'PROVISION_NONINTERACTIVE=true' "$config"
grep -Eq '^AUR_PACKAGES=.*onedrive-abraunegg' "$config"
grep -qx 'ENABLE_ONEDRIVE=true' "$config"
grep -qx 'ONEDRIVE_LINK_DIRS="Documents Pictures Videos"' "$config"
grep -qx 'ENABLE_FIRST_LOGIN_AUTH=true' "$config"
[[ -L $bin/archctl && -L $bin/arch-workstation-start && -L $bin/arch-workstation-build-usb ]] \
  || { echo 'Command symlinks were not created.' >&2; exit 1; }
[[ -d $state ]] || { echo 'State directory was not created.' >&2; exit 1; }
compgen -G "$backup/arch-workstation-before-*.tar.gz" >/dev/null || { echo 'Repository backup was not created.' >&2; exit 1; }
compgen -G "$backup/install.conf-before-*" >/dev/null || { echo 'Configuration backup was not created.' >&2; exit 1; }

echo 'Existing-install upgrade test passed.'
