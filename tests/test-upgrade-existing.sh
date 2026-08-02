#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

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
[[ -L $target/config/install.conf ]] || { echo 'Installed configuration symlink is missing.' >&2; exit 1; }
[[ $(readlink "$target/config/install.conf") == "$config" ]] || { echo 'Configuration symlink points to the wrong path.' >&2; exit 1; }
grep -qx 'DISK="/dev/test"' "$config"
grep -qx 'AUR_HELPER_PACKAGE="paru-bin"' "$config"
grep -qx 'AUR_NONINTERACTIVE=true' "$config"
grep -qx 'PROVISION_NONINTERACTIVE=true' "$config"
[[ -L $bin/archctl && -L $bin/arch-workstation-start ]] || { echo 'Command symlinks were not created.' >&2; exit 1; }
[[ -d $state ]] || { echo 'State directory was not created.' >&2; exit 1; }
compgen -G "$backup/arch-workstation-before-*.tar.gz" >/dev/null || { echo 'Repository backup was not created.' >&2; exit 1; }
compgen -G "$backup/install.conf-before-*" >/dev/null || { echo 'Configuration backup was not created.' >&2; exit 1; }

echo 'Existing-install upgrade test passed.'
