#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config/install.conf"
MODE=guided

# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/usb/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: ./usb/configure.sh [options]

Options:
  --config PATH    Configuration file to create or edit
  --guided        Run the guided configuration prompts (default)
  --editor        Open the file in $EDITOR after ensuring it exists
  --show          Print the resolved configuration summary
  --set K=V       Set an approved configuration value; may be repeated
  -h, --help      Show this help
USAGE
}

ensure_config() {
  if [[ ! -e $CONFIG_FILE ]]; then
    mkdir -p "$(dirname -- "$CONFIG_FILE")"
    cp "$REPO_ROOT/config/install.conf.example" "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE"
    info "Created $CONFIG_FILE from the example."
  fi
  [[ -f $CONFIG_FILE && ! -L $CONFIG_FILE ]] || die "Configuration must be a regular file: $CONFIG_FILE"
}

allowed_key() {
  case "$1" in
    DISK|ESP_SIZE_MIB|HOSTNAME|USERNAME|TIMEZONE|LOCALE|KEYMAP|X11_LAYOUT|CPU_VENDOR|GPU_VENDOR|KERNELS|FILESYSTEM|DESKTOP|LUKS_PASSPHRASE_FILE|USER_PASSWORD_FILE|TPM_PIN_FILE|INITIAL_INSTALL_SOURCE_MODE|ENABLE_MULTILIB|ENABLE_SSD_TRIM|ENABLE_AUR|AUR_HELPER|AUR_HELPER_PACKAGE|AUR_PACKAGES|AUR_NONINTERACTIVE|PROVISION_NONINTERACTIVE|ENABLE_DOCKER|DOCKER_ADD_USER_TO_GROUP|ENABLE_GAMING|ENABLE_SNAPSHOTS|ENABLE_T480|ENABLE_POWERSHELL_PROFILE|INSTALL_POWERSHELL_MODULES|INSTALL_VSCODE_EXTENSIONS|ENABLE_BLUETOOTH|ENABLE_SSH|MANAGE_DEFAULT_APPLICATIONS|DEFAULT_BROWSER|DEFAULT_MAIL_HANDLER|DEFAULT_FILE_MANAGER|DEFAULT_TERMINAL|DEFAULT_TEXT_EDITOR|DEFAULT_CODE_EDITOR|DEFAULT_IMAGE_VIEWER|DEFAULT_ARCHIVE_MANAGER|DEFAULT_MEDIA_PLAYER|DEFAULT_PDF_VIEWER|ENABLE_ONEDRIVE|ONEDRIVE_SYNC_DIR|ONEDRIVE_LINK_DIRS|ONEDRIVE_SKIP_DOTFILES|ONEDRIVE_SKIP_SYMLINKS|ONEDRIVE_USE_RECYCLE_BIN|ONEDRIVE_ENABLE_SERVICE|ONEDRIVE_INITIAL_SYNC_BACKGROUND|ONEDRIVE_NOTIFY_ON_COMPLETION|ENABLE_FIRST_LOGIN_AUTH|AUTH_GITHUB_CLI|GITHUB_GIT_PROTOCOL|AUTH_ONEDRIVE|AUTH_VSCODE|AUTH_EDGE|AUTH_STEAM|EDGE_PREPARE_BEFORE_OAUTH|ENABLE_SECURE_BOOT|REQUIRE_SETUP_MODE_AT_INSTALL|AUTO_PREPARE_SECURE_BOOT|SBCTL_ENROLL_MICROSOFT|ENABLE_TPM|REQUIRE_TPM|TPM_PCRS|TPM_WITH_PIN|TPM_PIN_MIN_LENGTH|TPM_PIN_NUMERIC_ONLY|STAGE_TPM_CREDENTIALS|T480_BATTERY_THRESHOLDS|T480_START_CHARGE|T480_STOP_CHARGE) return 0 ;;
    *) return 1 ;;
  esac
}

show_disks() {
  printf '\nAvailable whole disks:\n'
  lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,TYPE | sed -n '1,30p'
  printf '\n'
}

guided_configure() {
  local value
  load_config "$CONFIG_FILE"

  show_disks
  prompt_with_default value 'Target disk to erase during installation' "$DISK"
  set_shell_config_value "$CONFIG_FILE" DISK "$value"

  prompt_with_default value 'Hostname' "$HOSTNAME"
  set_shell_config_value "$CONFIG_FILE" HOSTNAME "$value"

  prompt_with_default value 'Linux username' "$USERNAME"
  set_shell_config_value "$CONFIG_FILE" USERNAME "$value"

  prompt_with_default value 'Timezone' "$TIMEZONE"
  set_shell_config_value "$CONFIG_FILE" TIMEZONE "$value"

  prompt_with_default value 'Locale' "$LOCALE"
  set_shell_config_value "$CONFIG_FILE" LOCALE "$value"

  prompt_with_default value 'Console keymap' "$KEYMAP"
  set_shell_config_value "$CONFIG_FILE" KEYMAP "$value"

  prompt_with_default value 'X11 keyboard layout' "$X11_LAYOUT"
  set_shell_config_value "$CONFIG_FILE" X11_LAYOUT "$value"

  prompt_with_default value 'CPU vendor (intel/amd)' "$CPU_VENDOR"
  set_shell_config_value "$CONFIG_FILE" CPU_VENDOR "${value,,}"

  prompt_with_default value 'GPU vendor (intel/amd/generic)' "$GPU_VENDOR"
  set_shell_config_value "$CONFIG_FILE" GPU_VENDOR "${value,,}"

  load_config "$CONFIG_FILE"
  prompt_boolean value 'Apply the ThinkPad T480 hardware role?' "$ENABLE_T480"
  set_shell_config_value "$CONFIG_FILE" ENABLE_T480 "$value"

  prompt_boolean value 'Prepare Secure Boot owner keys during installation?' "$ENABLE_SECURE_BOOT"
  set_shell_config_value "$CONFIG_FILE" ENABLE_SECURE_BOOT "$value"
  if bool_true "$value"; then
    set_shell_config_value "$CONFIG_FILE" REQUIRE_SETUP_MODE_AT_INSTALL true
    set_shell_config_value "$CONFIG_FILE" AUTO_PREPARE_SECURE_BOOT true
  fi

  prompt_boolean value 'Enable TPM2 unlock after Secure Boot is active?' "$ENABLE_TPM"
  set_shell_config_value "$CONFIG_FILE" ENABLE_TPM "$value"
  set_shell_config_value "$CONFIG_FILE" REQUIRE_TPM "$value"

  prompt_boolean value 'Require a daily TPM2 PIN?' "$TPM_WITH_PIN"
  set_shell_config_value "$CONFIG_FILE" TPM_WITH_PIN "$value"

  load_config "$CONFIG_FILE"
  prompt_boolean value 'Manage Xfce and XDG default application associations?' "$MANAGE_DEFAULT_APPLICATIONS"
  set_shell_config_value "$CONFIG_FILE" MANAGE_DEFAULT_APPLICATIONS "$value"

  load_config "$CONFIG_FILE"
  prompt_boolean value 'Install and configure the OneDrive sync client?' "$ENABLE_ONEDRIVE"
  set_shell_config_value "$CONFIG_FILE" ENABLE_ONEDRIVE "$value"
  if bool_true "$value"; then
    prompt_with_default value 'OneDrive directory relative to the user home' "$ONEDRIVE_SYNC_DIR"
    set_shell_config_value "$CONFIG_FILE" ONEDRIVE_SYNC_DIR "$value"
    prompt_with_default value 'Home folders to link into OneDrive' "$ONEDRIVE_LINK_DIRS"
    set_shell_config_value "$CONFIG_FILE" ONEDRIVE_LINK_DIRS "$value"
    prompt_boolean value 'Run the initial OneDrive sync in a background service?' "$ONEDRIVE_INITIAL_SYNC_BACKGROUND"
    set_shell_config_value "$CONFIG_FILE" ONEDRIVE_INITIAL_SYNC_BACKGROUND "$value"
  else
    set_shell_config_value "$CONFIG_FILE" AUTH_ONEDRIVE false
  fi

  load_config "$CONFIG_FILE"
  prompt_boolean value 'Run the supported-app authentication wizard at first graphical login?' "$ENABLE_FIRST_LOGIN_AUTH"
  set_shell_config_value "$CONFIG_FILE" ENABLE_FIRST_LOGIN_AUTH "$value"
  if bool_true "$value"; then
    prompt_boolean value 'Prepare Edge before browser-based authentication?' "$EDGE_PREPARE_BEFORE_OAUTH"
    set_shell_config_value "$CONFIG_FILE" EDGE_PREPARE_BEFORE_OAUTH "$value"
  fi

  load_config "$CONFIG_FILE"
  validate_config runtime
  chmod 0600 "$CONFIG_FILE"
  printf '\n'
  print_config_summary
  success "Saved configuration to $CONFIG_FILE"
}

sets=()
while (($#)); do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || die '--config requires a path.'
      CONFIG_FILE=$2
      shift 2
      ;;
    --guided)
      MODE=guided
      shift
      ;;
    --editor)
      MODE=editor
      shift
      ;;
    --show)
      MODE=show
      shift
      ;;
    --set)
      [[ $# -ge 2 ]] || die '--set requires KEY=VALUE.'
      sets+=("$2")
      MODE=set
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown configuration option: $1"
      ;;
  esac
done

ensure_config
if ((${#sets[@]})); then
  for assignment in "${sets[@]}"; do
    [[ $assignment == *=* ]] || die "Expected KEY=VALUE: $assignment"
    key=${assignment%%=*}
    value=${assignment#*=}
    allowed_key "$key" || die "This key is not editable through --set: $key"
    set_shell_config_value "$CONFIG_FILE" "$key" "$value"
  done
  load_config "$CONFIG_FILE"
  validate_config runtime
  chmod 0600 "$CONFIG_FILE"
  success "Updated $CONFIG_FILE"
  exit 0
fi

case "$MODE" in
  guided)
    guided_configure
    ;;
  editor)
    editor=${EDITOR:-vim}
    command -v "$editor" >/dev/null 2>&1 || die "Editor not found: $editor"
    "$editor" "$CONFIG_FILE"
    load_config "$CONFIG_FILE"
    validate_config runtime
    chmod 0600 "$CONFIG_FILE"
    ;;
  show)
    load_config "$CONFIG_FILE"
    validate_config runtime
    print_config_summary
    ;;
  *)
    die "Unknown configuration mode: $MODE"
    ;;
esac
