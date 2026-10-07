#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"

load_config "$ROOT/config/install.conf.example"
validate_config runtime

[[ $CPU_VENDOR == intel ]]
[[ $GPU_VENDOR == intel ]]
[[ $DESKTOP == xfce ]]
[[ $FILESYSTEM == btrfs ]]
[[ $KEYMAP == uk ]]
[[ $X11_LAYOUT == gb ]]
[[ $AUR_HELPER_PACKAGE == paru ]]
bool_true "$ENABLE_SECURE_BOOT"
bool_true "$AUTO_PREPARE_SECURE_BOOT"
bool_true "$REQUIRE_SETUP_MODE_AT_INSTALL"
bool_true "$ENABLE_TPM"
bool_true "$AUR_NONINTERACTIVE"
bool_true "$PROVISION_NONINTERACTIVE"
bool_true "$ENABLE_SSH"
bool_true "$MANAGE_DEFAULT_APPLICATIONS"
[[ $DEFAULT_BROWSER == edge ]]
[[ $DEFAULT_FILE_MANAGER == thunar ]]
[[ $DEFAULT_TERMINAL == xfce4-terminal ]]
[[ $DEFAULT_MEDIA_PLAYER == mpv ]]
[[ -z $XFCE_TERMINAL_CUSTOM_COMMAND ]]
grep -Fq -- '--extra-vars "$(terminal_command_extra_vars)"' "$ROOT/scripts/provision.sh"
grep -Fq 'scripts/configure-xfce-terminal.sh' "$ROOT/ansible/roles/desktop/tasks/main.yml"
bool_true "$ENABLE_ONEDRIVE"
[[ $ONEDRIVE_SYNC_DIR == OneDrive ]]
[[ -z $ONEDRIVE_PROFILES ]]
[[ $ONEDRIVE_LINK_DIRS == 'Documents Pictures Videos' ]]
bool_true "$ENABLE_FIRST_LOGIN_AUTH"
bool_true "$AUTH_GITHUB_CLI"
bool_true "$AUTH_ONEDRIVE"

invalid=$(mktemp)
trap 'rm -f "$invalid"' EXIT

expect_invalid() {
  local expression=$1 message=$2
  cp "$ROOT/config/install.conf.example" "$invalid"
  eval "$expression"
  if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
    echo "$message" >&2
    exit 1
  fi
}

expect_invalid "sed -i 's/^GPU_VENDOR=.*/GPU_VENDOR=\"nvidia\"/' '$invalid'" \
  'Invalid GPU profile unexpectedly passed validation.'
expect_invalid "sed -i 's/^GPU_VENDOR=.*/GPU_VENDOR=\"generic\"/' '$invalid'" \
  'Generic GPU with gaming enabled unexpectedly passed validation.'
expect_invalid "sed -i 's/^ENABLE_MULTILIB=.*/ENABLE_MULTILIB=false/' '$invalid'" \
  'Gaming without multilib unexpectedly passed validation.'
expect_invalid "sed -i 's/^ENABLE_SECURE_BOOT=.*/ENABLE_SECURE_BOOT=false/' '$invalid'" \
  'TPM or automatic Secure Boot preparation without Secure Boot unexpectedly passed validation.'
expect_invalid "sed -i 's/^REQUIRE_SETUP_MODE_AT_INSTALL=.*/REQUIRE_SETUP_MODE_AT_INSTALL=false/' '$invalid'" \
  'Automatic Secure Boot preparation without required Setup Mode unexpectedly passed validation.'
expect_invalid "sed -i 's/^AUR_HELPER_PACKAGE=.*/AUR_HELPER_PACKAGE=\"unknown\"/' '$invalid'" \
  'Unknown AUR helper package unexpectedly passed validation.'
expect_invalid "sed -i 's/^KERNELS=.*/KERNELS=\"linux ..\/evil\"/' '$invalid'" \
  'Unsafe kernel package token unexpectedly passed validation.'
expect_invalid "sed -i 's/^AUR_PACKAGES=.*/AUR_PACKAGES=\"--remove-all\"/' '$invalid'" \
  'Option-like AUR package token unexpectedly passed validation.'
expect_invalid "sed -i 's/^ENABLE_SSH=.*/ENABLE_SSH=perhaps/' '$invalid'" \
  'Invalid boolean unexpectedly passed validation.'
expect_invalid "sed -i 's/^X11_LAYOUT=.*/X11_LAYOUT=\"gb;evil\"/' '$invalid'" \
  'Invalid X11 layout unexpectedly passed validation.'
expect_invalid "sed -i 's/^DEFAULT_BROWSER=.*/DEFAULT_BROWSER=\"firefox\"/' '$invalid'" \
  'Unsupported default browser unexpectedly passed validation.'

# An older installed policy need not contain the new key. Loading it must
# retain the disabled default and still produce a usable Ansible value.
sed '/^XFCE_TERMINAL_CUSTOM_COMMAND=/d' "$ROOT/config/install.conf.example" > "$invalid"
load_config "$invalid"
validate_config runtime
[[ -z $XFCE_TERMINAL_CUSTOM_COMMAND ]]
terminal_command_extra_vars | python3 -c 'import json, sys; assert json.load(sys.stdin) == {"xfce_terminal_custom_command": ""}'

# Spaces, quotes, equal signs and shell/Ansible-looking tokens must survive as
# data, never become a second extra-var or be evaluated by a shell.
XFCE_TERMINAL_CUSTOM_COMMAND='env TITLE="work desk" sh -c '\''echo $HOME; echo {{ 1 + 1 }}; echo x=y'\'''
export XFCE_TERMINAL_CUSTOM_COMMAND
terminal_command_extra_vars | python3 -c 'import json, os, sys; assert json.load(sys.stdin) == {"xfce_terminal_custom_command": os.environ["XFCE_TERMINAL_CUSTOM_COMMAND"]}'
if ! (validate_config runtime) >/dev/null 2>&1; then
  echo 'Valid terminal command unexpectedly failed validation.' >&2
  exit 1
fi
XFCE_TERMINAL_CUSTOM_COMMAND=$'echo safe\nRunCustomCommand=TRUE'
if (validate_config runtime) >/dev/null 2>&1; then
  echo 'Multiline terminal command unexpectedly passed validation.' >&2
  exit 1
fi

echo 'Configuration validation tests passed.'
