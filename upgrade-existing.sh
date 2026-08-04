#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="${ARCH_WORKSTATION_TARGET:-/opt/arch-workstation}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
BACKUP_DIR="${ARCH_WORKSTATION_BACKUP_DIR:-/var/backups/arch-workstation}"
BIN_DIR="${ARCH_WORKSTATION_BIN_DIR:-/usr/local/bin}"
MIGRATION_STATE_DIR="${ARCH_WORKSTATION_STATE_DIR:-/var/lib/arch-workstation}"
CONFIG_GROUP="${ARCH_WORKSTATION_CONFIG_GROUP:-wheel}"
APPLY_AUTOMATION_DEFAULTS=true
UPGRADE_COMMITTED=false
CONFIG_CHANGED=false

usage() {
  cat <<'USAGE'
Usage: ./upgrade-existing.sh [--keep-interactive-aur]

Install this repository over an existing arch-workstation installation while
preserving the machine configuration and security state. Run it from an
extracted release directory, not from /opt/arch-workstation itself.

Options:
  --keep-interactive-aur  Preserve interactive AUR review/update prompts
USAGE
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

while (($#)); do
  case "$1" in
    --keep-interactive-aur)
      APPLY_AUTOMATION_DEFAULTS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -r $SOURCE_ROOT/VERSION ]] || { echo "VERSION is missing from $SOURCE_ROOT" >&2; exit 1; }
[[ -r $SOURCE_ROOT/archctl ]] || { echo "archctl is missing from $SOURCE_ROOT" >&2; exit 1; }
[[ -r $CONFIG_FILE ]] || { echo "Existing configuration not found: $CONFIG_FILE" >&2; exit 1; }
[[ -d $TARGET_ROOT ]] || { echo "Existing installation not found: $TARGET_ROOT" >&2; exit 1; }
[[ $(readlink -f "$SOURCE_ROOT") != $(readlink -f "$TARGET_ROOT") ]] \
  || { echo "Extract the release somewhere outside $TARGET_ROOT before upgrading." >&2; exit 1; }

for script in "$SOURCE_ROOT"/*.sh "$SOURCE_ROOT"/archctl "$SOURCE_ROOT"/scripts/*.sh \
  "$SOURCE_ROOT"/scripts/install/*.sh "$SOURCE_ROOT"/scripts/lib/*.sh \
  "$SOURCE_ROOT"/scripts/security/*.sh "$SOURCE_ROOT"/usb/*.sh \
  "$SOURCE_ROOT"/usb/lib/*.sh "$SOURCE_ROOT"/usb/live/* "$SOURCE_ROOT"/tests/*.sh; do
  bash -n "$script"
done

version=$(<"$SOURCE_ROOT/VERSION")
timestamp=$(date +'%Y%m%d-%H%M%S')
target_parent=$(dirname "$TARGET_ROOT")
target_name=$(basename "$TARGET_ROOT")
backup="$BACKUP_DIR/arch-workstation-before-${version}-${timestamp}.tar.gz"
stage=$(mktemp -d "$target_parent/.arch-workstation-new.XXXXXX")
old="$target_parent/.arch-workstation-old-${timestamp}"

cleanup() {
  if [[ $UPGRADE_COMMITTED != true && -e $old ]]; then
    rm -rf "$TARGET_ROOT" 2>/dev/null || true
    mv "$old" "$TARGET_ROOT" || true
  fi
  if [[ $UPGRADE_COMMITTED != true && $CONFIG_CHANGED == true && -r ${config_backup:-} ]]; then
    install -o root -g "$CONFIG_GROUP" -m 0640 "$config_backup" "$CONFIG_FILE" || true
  fi
  if [[ -n ${stage:-} ]]; then
    rm -rf "$stage"
  fi
}
trap cleanup EXIT

install -d -m 0700 "$BACKUP_DIR"
tar -C "$target_parent" -czf "$backup" "$target_name"
chmod 0600 "$backup"

echo "Staging arch-workstation $version. Backup: $backup"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='config/install.conf' \
  --exclude='config/usb-secrets.json' \
  --exclude='config/secrets.conf' \
  --exclude='config/secrets.env' \
  --exclude='*.secret' \
  --exclude='*.key' \
  --exclude='*.pem' \
  --exclude='*.gpg' \
  --exclude='*.iso' \
  --exclude='*.bundle' \
  --exclude='usb/output/' \
  --exclude='usb/work/' \
  --exclude='*.zip' \
  --exclude='*.tar.gz' \
  "$SOURCE_ROOT/" "$stage/"

rm -f "$stage/config/install.conf"
ln -s "$CONFIG_FILE" "$stage/config/install.conf"
printf '%s\n' "release-$version" > "$stage/BUILD_COMMIT"
chmod 0755 "$stage/install.sh" "$stage/start.sh" "$stage/archctl" \
  "$stage/upgrade-existing.sh" "$stage/build-usb.sh"
find "$stage/scripts" "$stage/usb" "$stage/tests" -type f -name '*.sh' -exec chmod 0755 {} +
chown -R root:root "$stage"

config_backup="$BACKUP_DIR/install.conf-before-${version}-${timestamp}"
install -m 0600 "$CONFIG_FILE" "$config_backup"

set_config_value() {
  local key=$1 assignment=$2 temp
  temp=$(mktemp)
  awk -v key="$key" -v assignment="$assignment" '
    $0 ~ "^" key "=" {
      if (!written) print assignment
      written = 1
      next
    }
    { print }
    END {
      if (!written) {
        print ""
        print assignment
      }
    }
  ' "$CONFIG_FILE" > "$temp"
  install -o root -g "$CONFIG_GROUP" -m 0640 "$temp" "$CONFIG_FILE"
  rm -f "$temp"
}

ensure_config_value() {
  local key=$1 assignment=$2
  grep -q "^${key}=" "$CONFIG_FILE" || set_config_value "$key" "$assignment"
}

append_config_package() {
  local key=$1 package=$2 current quoted item found=false
  local -a current_packages=()
  current=$(bash -c 'source "$1"; printf "%s" "${!2:-}"' _ "$CONFIG_FILE" "$key")
  read -r -a current_packages <<< "$current"
  for item in "${current_packages[@]}"; do
    if [[ $item == "$package" ]]; then
      found=true
      break
    fi
  done
  if [[ $found == false ]]; then
    current="${current:+$current }$package"
    printf -v quoted '%q' "$current"
    set_config_value "$key" "$key=$quoted"
  fi
}
set_config_value AUR_HELPER_PACKAGE 'AUR_HELPER_PACKAGE="paru"'
append_config_package AUR_PACKAGES onedrive-abraunegg
ensure_config_value ENABLE_ONEDRIVE 'ENABLE_ONEDRIVE=true'
ensure_config_value ONEDRIVE_SYNC_DIR 'ONEDRIVE_SYNC_DIR="OneDrive"'
ensure_config_value ONEDRIVE_LINK_DIRS 'ONEDRIVE_LINK_DIRS="Documents Pictures Videos"'
ensure_config_value ONEDRIVE_SKIP_DOTFILES 'ONEDRIVE_SKIP_DOTFILES=true'
ensure_config_value ONEDRIVE_SKIP_SYMLINKS 'ONEDRIVE_SKIP_SYMLINKS=true'
ensure_config_value ONEDRIVE_USE_RECYCLE_BIN 'ONEDRIVE_USE_RECYCLE_BIN=true'
ensure_config_value ONEDRIVE_ENABLE_SERVICE 'ONEDRIVE_ENABLE_SERVICE=true'
ensure_config_value ONEDRIVE_INITIAL_SYNC_BACKGROUND 'ONEDRIVE_INITIAL_SYNC_BACKGROUND=true'
ensure_config_value ONEDRIVE_NOTIFY_ON_COMPLETION 'ONEDRIVE_NOTIFY_ON_COMPLETION=true'
ensure_config_value ENABLE_FIRST_LOGIN_AUTH 'ENABLE_FIRST_LOGIN_AUTH=true'
ensure_config_value AUTH_GITHUB_CLI 'AUTH_GITHUB_CLI=true'
ensure_config_value GITHUB_GIT_PROTOCOL 'GITHUB_GIT_PROTOCOL="https"'
ensure_config_value AUTH_ONEDRIVE 'AUTH_ONEDRIVE=true'
ensure_config_value AUTH_VSCODE 'AUTH_VSCODE=true'
ensure_config_value AUTH_EDGE 'AUTH_EDGE=true'
ensure_config_value AUTH_STEAM 'AUTH_STEAM=true'
ensure_config_value EDGE_PREPARE_BEFORE_OAUTH 'EDGE_PREPARE_BEFORE_OAUTH=true'
set_config_value PROVISION_NONINTERACTIVE 'PROVISION_NONINTERACTIVE=true'
if [[ $APPLY_AUTOMATION_DEFAULTS == true ]]; then
  set_config_value AUR_NONINTERACTIVE 'AUR_NONINTERACTIVE=true'
fi
CONFIG_CHANGED=true

mv "$TARGET_ROOT" "$old"
mv "$stage" "$TARGET_ROOT"
stage=""

install -d -m 0755 "$BIN_DIR" "$MIGRATION_STATE_DIR"
ln -sfn "$TARGET_ROOT/archctl" "$BIN_DIR/archctl"
ln -sfn "$TARGET_ROOT/start.sh" "$BIN_DIR/arch-workstation-start"
ln -sfn "$TARGET_ROOT/build-usb.sh" "$BIN_DIR/arch-workstation-build-usb"

UPGRADE_COMMITTED=true
rm -rf "$old"
trap - EXIT
echo "Upgrade to arch-workstation $version completed."
echo "Run as your normal user: archctl finish"
