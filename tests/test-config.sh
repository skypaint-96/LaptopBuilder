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
bool_true "$ENABLE_SECURE_BOOT"
bool_true "$ENABLE_TPM"
[[ $INSTALL_SOURCE_MODE == auto ]]
[[ -z $EXTRA_OFFICIAL_PACKAGES ]]

invalid=$(mktemp)
trap 'rm -f "$invalid"' EXIT
cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^GPU_VENDOR=.*/GPU_VENDOR="nvidia"/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'Invalid GPU profile unexpectedly passed validation.' >&2
  exit 1
fi

cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^GPU_VENDOR=.*/GPU_VENDOR="generic"/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'Generic GPU with gaming enabled unexpectedly passed validation.' >&2
  exit 1
fi

cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^ENABLE_MULTILIB=.*/ENABLE_MULTILIB=false/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'Gaming without multilib unexpectedly passed validation.' >&2
  exit 1
fi

cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^ENABLE_SECURE_BOOT=.*/ENABLE_SECURE_BOOT=false/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'TPM without Secure Boot unexpectedly passed validation.' >&2
  exit 1
fi

cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^ENABLE_SSH=.*/ENABLE_SSH=perhaps/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'Invalid boolean unexpectedly passed validation.' >&2
  exit 1
fi


cp "$ROOT/config/install.conf.example" "$invalid"
sed -i 's/^INSTALL_SOURCE_MODE=.*/INSTALL_SOURCE_MODE="something-else"/' "$invalid"
if (load_config "$invalid" && validate_config runtime) >/dev/null 2>&1; then
  echo 'Invalid installation source unexpectedly passed validation.' >&2
  exit 1
fi

echo 'Configuration validation tests passed.'
