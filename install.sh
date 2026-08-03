#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$REPO_ROOT/config/install.conf"
PREFLIGHT_ONLY=false
CLI_NONINTERACTIVE=false
REBOOT_FIRMWARE=false

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

Options:
  --config PATH       Installation configuration file
  --preflight-only    Validate the ISO, firmware, network, disk, and configuration only
  --non-interactive   Override NONINTERACTIVE=true (requires exact WIPE_CONFIRMATION)
  --reboot-firmware   Enter firmware setup automatically after successful installation
  -h, --help          Show this help
EOF
}

while (($#)); do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "--config requires a path" >&2; exit 2; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=true
      shift
      ;;
    --non-interactive)
      CLI_NONINTERACTIVE=true
      shift
      ;;
    --reboot-firmware)
      REBOOT_FIRMWARE=true
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

# shellcheck source=scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=scripts/install/01-preflight.sh
source "$REPO_ROOT/scripts/install/01-preflight.sh"
# shellcheck source=scripts/install/10-disk.sh
source "$REPO_ROOT/scripts/install/10-disk.sh"
# shellcheck source=scripts/install/20-base.sh
source "$REPO_ROOT/scripts/install/20-base.sh"

require_root
[[ -r "$CONFIG_FILE" ]] || die "Configuration not found: $CONFIG_FILE. Copy config/install.conf.example first."

load_config "$CONFIG_FILE"
if bool_true "$CLI_NONINTERACTIVE"; then
  NONINTERACTIVE=true
fi
validate_config install

INSTALL_COMPLETED=false
cleanup_on_exit() {
  local code=$?
  unset INSTALL_LUKS_PASSPHRASE INSTALL_USER_PASSWORD INSTALL_TPM_PIN \
    INSTALL_LUKS_RECOVERY_CREDENTIAL INSTALL_TPM_PIN_CREDENTIAL 2>/dev/null || true
  if ! bool_true "$INSTALL_COMPLETED"; then
    warn "Installation did not complete; cleaning mounted target resources."
    cleanup_target || true
  fi
  exit "$code"
}
trap cleanup_on_exit EXIT

preflight_install
if bool_true "$PREFLIGHT_ONLY"; then
  INSTALL_COMPLETED=true
  trap - EXIT
  success "Preflight completed. No disk changes were made."
  exit 0
fi

# Collect all installation credentials before touching the target disk. They remain
# unexported shell variables and are cleared after their respective installation step.
read_secret_into INSTALL_LUKS_PASSPHRASE "$LUKS_PASSPHRASE_FILE" "LUKS passphrase" true
INSTALL_LUKS_RECOVERY_CREDENTIAL=$INSTALL_LUKS_PASSPHRASE
read_secret_into INSTALL_USER_PASSWORD "$USER_PASSWORD_FILE" "Password for $USERNAME" true
if bool_true "$ENABLE_TPM" && bool_true "$TPM_WITH_PIN"; then
  read_secret_into INSTALL_TPM_PIN "$TPM_PIN_FILE" "TPM2 PIN" true
  if bool_true "$TPM_PIN_NUMERIC_ONLY" && [[ ! $INSTALL_TPM_PIN =~ ^[0-9]+$ ]]; then
    die "The TPM2 PIN must contain digits only."
  fi
  ((${#INSTALL_TPM_PIN} >= TPM_PIN_MIN_LENGTH)) \
    || die "The TPM2 PIN must be at least $TPM_PIN_MIN_LENGTH characters."
  INSTALL_TPM_PIN_CREDENTIAL=$INSTALL_TPM_PIN
  unset INSTALL_TPM_PIN
fi

prepare_disk
install_base_system
configure_base_system
prepare_target_secure_boot
create_efi_boot_entry

sync
cleanup_target
INSTALL_COMPLETED=true
trap - EXIT

cat <<EOF

Installation completed successfully.

Next steps:
  1. Reboot into firmware setup and enable Secure Boot without clearing or restoring keys.
  2. Remove the Arch installation media and boot the installed system.
  3. Unlock once with the retained LUKS passphrase and log in as $USERNAME.
  4. Run: archctl finish

That single resumable command provisions the workstation, enrols TPM2 unlock, and
runs the final audit. The installed repository is /opt/arch-workstation.
EOF

if bool_true "$REBOOT_FIRMWARE"; then
  info "Requesting a reboot directly into firmware setup."
  if ! systemctl reboot --firmware-setup; then
    warn "The firmware-setup reboot request was not supported. Reboot normally and press the firmware setup key."
  fi
fi
