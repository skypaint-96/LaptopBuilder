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
[[ $AUR_HELPER_PACKAGE == paru-bin ]]
bool_true "$ENABLE_SECURE_BOOT"
bool_true "$AUTO_PREPARE_SECURE_BOOT"
bool_true "$REQUIRE_SETUP_MODE_AT_INSTALL"
bool_true "$ENABLE_TPM"
bool_true "$AUR_NONINTERACTIVE"
bool_true "$PROVISION_NONINTERACTIVE"

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

echo 'Configuration validation tests passed.'
