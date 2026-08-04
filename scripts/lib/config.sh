#!/usr/bin/env bash

set_config_defaults() {
  DISK=""
  ESP_SIZE_MIB=1024
  HOSTNAME="arch-t480"
  USERNAME="mason"
  TIMEZONE="Europe/London"
  LOCALE="en_GB.UTF-8"
  KEYMAP="uk"
  X11_LAYOUT="gb"
  CPU_VENDOR="intel"
  GPU_VENDOR="intel"
  KERNELS="linux linux-lts"
  FILESYSTEM="btrfs"
  DESKTOP="xfce"

  ENABLE_MULTILIB=true
  ENABLE_SSD_TRIM=true
  ENABLE_AUR=true
  AUR_HELPER="paru"
  AUR_HELPER_PACKAGE="paru"
  AUR_PACKAGES="microsoft-edge-stable-bin visual-studio-code-bin powershell-bin onedrive-abraunegg"
  AUR_NONINTERACTIVE=true
  PROVISION_NONINTERACTIVE=true

  ENABLE_DOCKER=true
  DOCKER_ADD_USER_TO_GROUP=true
  ENABLE_GAMING=true
  ENABLE_SNAPSHOTS=true
  ENABLE_T480=true
  ENABLE_POWERSHELL_PROFILE=true
  INSTALL_POWERSHELL_MODULES=false
  INSTALL_VSCODE_EXTENSIONS=true
  ENABLE_BLUETOOTH=true
  ENABLE_SSH=true

  ENABLE_ONEDRIVE=true
  ONEDRIVE_SYNC_DIR="OneDrive"
  ONEDRIVE_LINK_DIRS="Documents Pictures Videos"
  ONEDRIVE_SKIP_DOTFILES=true
  ONEDRIVE_SKIP_SYMLINKS=true
  ONEDRIVE_USE_RECYCLE_BIN=true
  ONEDRIVE_ENABLE_SERVICE=true

  ENABLE_FIRST_LOGIN_AUTH=true
  AUTH_GITHUB_CLI=true
  GITHUB_GIT_PROTOCOL="https"
  AUTH_ONEDRIVE=true
  AUTH_VSCODE=true
  AUTH_EDGE=true
  AUTH_STEAM=true

  ENABLE_SECURE_BOOT=true
  REQUIRE_SETUP_MODE_AT_INSTALL=true
  AUTO_PREPARE_SECURE_BOOT=true
  SBCTL_ENROLL_MICROSOFT=true
  ENABLE_TPM=true
  REQUIRE_TPM=true
  TPM_PCRS="7"
  TPM_WITH_PIN=true
  TPM_PIN_MIN_LENGTH=6
  TPM_PIN_NUMERIC_ONLY=true
  STAGE_TPM_CREDENTIALS=true

  T480_BATTERY_THRESHOLDS=false
  T480_START_CHARGE=40
  T480_STOP_CHARGE=80

  LUKS_PASSPHRASE_FILE=""
  USER_PASSWORD_FILE=""
  TPM_PIN_FILE=""
  INITIAL_INSTALL_SOURCE_MODE="live"
  NONINTERACTIVE=false
  WIPE_CONFIRMATION=""
  ALLOW_NON_ARCHISO=false
}

load_config() {
  local path=$1
  set_config_defaults
  # shellcheck source=/dev/null
  source "$path"
  CONFIG_FILE="$path"
  if [[ -n $DISK && -e $DISK ]]; then
    DISK=$(readlink -f "$DISK")
  fi
}

validate_bool() {
  local name=$1 value=${!1}
  case "${value,,}" in
    1|0|true|false|yes|no|on|off) ;;
    *) die "$name must be a boolean, not: $value" ;;
  esac
}

validate_package_list() {
  local name=$1 value=${!1} package
  local -a packages
  read -r -a packages <<< "$value"
  for package in "${packages[@]}"; do
    [[ $package =~ ^[a-zA-Z0-9@._+:-]+$ && $package != -* ]] \
      || die "$name contains an invalid package token: $package"
  done
}

validate_simple_name_list() {
  local name=$1 value=${!1} item
  local -a items
  read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    [[ $item =~ ^[a-zA-Z0-9._-]+$ && $item != .* && $item != -* ]] \
      || die "$name contains an invalid directory name: $item"
  done
}

validate_home_relative_path() {
  local name=$1 value=${!1} component
  local -a components
  [[ -n $value && $value != /* && $value != '~'* && $value != *$'\n'* ]] \
    || die "$name must be a non-empty path relative to the user's home directory."
  IFS='/' read -r -a components <<< "$value"
  for component in "${components[@]}"; do
    [[ -n $component && $component != . && $component != .. \
      && $component =~ ^[a-zA-Z0-9._-]+$ ]] \
      || die "$name contains an unsafe path component: $component"
  done
}

validate_config() {
  local mode=${1:-runtime}
  local boolean

  if [[ $mode == install ]]; then
    [[ -n $DISK ]] || die "DISK is required."
    [[ $DISK == /dev/* ]] || die "DISK must be a /dev path."
    [[ $ESP_SIZE_MIB =~ ^[0-9]+$ && $ESP_SIZE_MIB -ge 512 ]] || die "ESP_SIZE_MIB must be at least 512."
  fi

  [[ $HOSTNAME =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]] || die "Invalid HOSTNAME: $HOSTNAME"
  [[ $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid USERNAME: $USERNAME"
  [[ -e /usr/share/zoneinfo/$TIMEZONE ]] || die "Unknown TIMEZONE: $TIMEZONE"
  [[ $LOCALE == *UTF-8 ]] || die "LOCALE must be UTF-8."
  [[ $KEYMAP =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid KEYMAP: $KEYMAP"
  [[ $X11_LAYOUT =~ ^[a-zA-Z0-9_,+:-]+$ ]] || die "Invalid X11_LAYOUT: $X11_LAYOUT"
  [[ $CPU_VENDOR == intel || $CPU_VENDOR == amd ]] || die "CPU_VENDOR must be intel or amd."
  [[ $GPU_VENDOR == intel || $GPU_VENDOR == amd || $GPU_VENDOR == generic ]] || die "GPU_VENDOR must be intel, amd, or generic."
  if bool_true "$ENABLE_T480" && [[ $CPU_VENDOR != intel ]]; then
    die "The ThinkPad T480 profile requires CPU_VENDOR=intel."
  fi
  [[ $FILESYSTEM == btrfs ]] || die "Only FILESYSTEM=btrfs is currently supported."
  [[ $DESKTOP == xfce ]] || die "Only DESKTOP=xfce is currently supported."
  [[ -n $KERNELS ]] || die "At least one kernel is required."
  validate_package_list KERNELS
  validate_package_list AUR_PACKAGES
  [[ $AUR_HELPER == paru ]] || die "Only AUR_HELPER=paru is currently supported."
  [[ $AUR_HELPER_PACKAGE == paru || $AUR_HELPER_PACKAGE == paru-bin ]] \
    || die "AUR_HELPER_PACKAGE must be paru or paru-bin."
  validate_home_relative_path ONEDRIVE_SYNC_DIR
  validate_simple_name_list ONEDRIVE_LINK_DIRS
  [[ $GITHUB_GIT_PROTOCOL == https || $GITHUB_GIT_PROTOCOL == ssh ]] \
    || die "GITHUB_GIT_PROTOCOL must be https or ssh."
  [[ $TPM_PCRS =~ ^[0-9]+([+][0-9]+)*$ ]] || die "TPM_PCRS must look like 7 or 7+11."
  [[ $TPM_PIN_MIN_LENGTH =~ ^[0-9]+$ ]] || die "TPM_PIN_MIN_LENGTH must be an integer."
  ((TPM_PIN_MIN_LENGTH >= 4 && TPM_PIN_MIN_LENGTH <= 64)) || die "TPM_PIN_MIN_LENGTH must be between 4 and 64."
  [[ $INITIAL_INSTALL_SOURCE_MODE == live || $INITIAL_INSTALL_SOURCE_MODE == offline ]] \
    || die "INITIAL_INSTALL_SOURCE_MODE must be live or offline."
  [[ $T480_START_CHARGE =~ ^[0-9]+$ && $T480_STOP_CHARGE =~ ^[0-9]+$ ]] || die "Battery thresholds must be integers."
  ((T480_START_CHARGE >= 0 && T480_START_CHARGE < T480_STOP_CHARGE && T480_STOP_CHARGE <= 100)) || die "Invalid T480 battery threshold range."

  for boolean in \
    ENABLE_MULTILIB ENABLE_SSD_TRIM ENABLE_AUR AUR_NONINTERACTIVE PROVISION_NONINTERACTIVE \
    ENABLE_DOCKER DOCKER_ADD_USER_TO_GROUP ENABLE_GAMING ENABLE_SNAPSHOTS ENABLE_T480 \
    ENABLE_POWERSHELL_PROFILE INSTALL_POWERSHELL_MODULES INSTALL_VSCODE_EXTENSIONS \
    ENABLE_BLUETOOTH ENABLE_SSH ENABLE_ONEDRIVE ONEDRIVE_SKIP_DOTFILES \
    ONEDRIVE_SKIP_SYMLINKS ONEDRIVE_USE_RECYCLE_BIN ONEDRIVE_ENABLE_SERVICE \
    ENABLE_FIRST_LOGIN_AUTH AUTH_GITHUB_CLI AUTH_ONEDRIVE AUTH_VSCODE AUTH_EDGE AUTH_STEAM \
    ENABLE_SECURE_BOOT REQUIRE_SETUP_MODE_AT_INSTALL \
    AUTO_PREPARE_SECURE_BOOT SBCTL_ENROLL_MICROSOFT ENABLE_TPM REQUIRE_TPM TPM_WITH_PIN \
    TPM_PIN_NUMERIC_ONLY STAGE_TPM_CREDENTIALS T480_BATTERY_THRESHOLDS \
    NONINTERACTIVE ALLOW_NON_ARCHISO; do
    validate_bool "$boolean"
  done

  if bool_true "$ENABLE_GAMING" && ! bool_true "$ENABLE_MULTILIB"; then
    die "ENABLE_GAMING=true requires ENABLE_MULTILIB=true for Steam and 32-bit graphics userspace."
  fi
  if bool_true "$ENABLE_GAMING" && [[ $GPU_VENDOR == generic ]]; then
    die "ENABLE_GAMING=true requires GPU_VENDOR=intel or amd so the Vulkan provider is explicit."
  fi
  if bool_true "$AUTO_PREPARE_SECURE_BOOT" && ! bool_true "$ENABLE_SECURE_BOOT"; then
    die "AUTO_PREPARE_SECURE_BOOT=true requires ENABLE_SECURE_BOOT=true."
  fi
  if bool_true "$AUTO_PREPARE_SECURE_BOOT" && ! bool_true "$REQUIRE_SETUP_MODE_AT_INSTALL"; then
    die "AUTO_PREPARE_SECURE_BOOT=true requires REQUIRE_SETUP_MODE_AT_INSTALL=true."
  fi
  if bool_true "$ENABLE_TPM" && ! bool_true "$ENABLE_SECURE_BOOT"; then
    die "ENABLE_TPM=true requires ENABLE_SECURE_BOOT=true in this measured-boot design."
  fi
  if bool_true "$REQUIRE_TPM" && ! bool_true "$ENABLE_TPM"; then
    die "REQUIRE_TPM=true is inconsistent with ENABLE_TPM=false."
  fi
  if bool_true "$TPM_WITH_PIN" && ! bool_true "$ENABLE_TPM"; then
    die "TPM_WITH_PIN=true requires ENABLE_TPM=true."
  fi
  if bool_true "$STAGE_TPM_CREDENTIALS" && ! bool_true "$ENABLE_TPM"; then
    die "STAGE_TPM_CREDENTIALS=true requires ENABLE_TPM=true."
  fi
  if bool_true "$ENABLE_ONEDRIVE" && ! bool_true "$ENABLE_AUR"; then
    die "ENABLE_ONEDRIVE=true requires ENABLE_AUR=true for onedrive-abraunegg."
  fi
  if bool_true "$AUTH_ONEDRIVE" && ! bool_true "$ENABLE_ONEDRIVE"; then
    die "AUTH_ONEDRIVE=true requires ENABLE_ONEDRIVE=true."
  fi
  if ! bool_true "$ENABLE_AUR" && \
    { bool_true "$ENABLE_POWERSHELL_PROFILE" || bool_true "$INSTALL_VSCODE_EXTENSIONS"; }; then
    die "PowerShell profile or VS Code extension setup requires ENABLE_AUR=true with the configured binary packages."
  fi
}

print_config_summary() {
  cat <<EOF
Install target : $DISK
Host/user      : $HOSTNAME / $USERNAME
Locale         : $LOCALE, $TIMEZONE, console $KEYMAP, X11 $X11_LAYOUT
Hardware       : CPU $CPU_VENDOR, GPU $GPU_VENDOR
Storage        : GPT, ${ESP_SIZE_MIB} MiB ESP, LUKS2, Btrfs
Kernels        : $KERNELS
Desktop        : Xfce on X11
Secure Boot    : $ENABLE_SECURE_BOOT (Setup Mode required now: $REQUIRE_SETUP_MODE_AT_INSTALL)
Auto SB prepare : $AUTO_PREPARE_SECURE_BOOT
Microsoft certs: $SBCTL_ENROLL_MICROSOFT
TPM2           : $ENABLE_TPM (PCRs: $TPM_PCRS, PIN: $TPM_WITH_PIN, staged credentials: $STAGE_TPM_CREDENTIALS)
Snapshots      : $ENABLE_SNAPSHOTS
SSD TRIM       : $ENABLE_SSD_TRIM
Docker/gaming  : $ENABLE_DOCKER / $ENABLE_GAMING
AUR bootstrap  : $AUR_HELPER_PACKAGE (non-interactive: $AUR_NONINTERACTIVE)
SSH server     : $ENABLE_SSH
OneDrive       : $ENABLE_ONEDRIVE ($ONEDRIVE_SYNC_DIR; links: $ONEDRIVE_LINK_DIRS)
First-login auth: $ENABLE_FIRST_LOGIN_AUTH (GitHub: $AUTH_GITHUB_CLI, OneDrive: $AUTH_ONEDRIVE, VS Code: $AUTH_VSCODE, Edge: $AUTH_EDGE, Steam: $AUTH_STEAM)
EOF
}
