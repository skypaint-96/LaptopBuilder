#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$REPO_ROOT/config/install.conf"
PREFLIGHT_ONLY=false
CLI_NONINTERACTIVE=false

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

Options:
  --config PATH       Installation configuration file
  --preflight-only    Validate the ISO, firmware, network, disk, and configuration only
  --non-interactive   Override NONINTERACTIVE=true (requires exact WIPE_CONFIRMATION)
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
# shellcheck source=scripts/lib/packages.sh
source "$REPO_ROOT/scripts/lib/packages.sh"
# shellcheck source=scripts/lib/install-source.sh
source "$REPO_ROOT/scripts/lib/install-source.sh"
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
resolve_install_source

INSTALL_COMPLETED=false
cleanup_on_exit() {
  local code=$?
  unset INSTALL_LUKS_PASSPHRASE INSTALL_USER_PASSWORD 2>/dev/null || true
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

# Collect both secrets before touching the target disk. They remain unexported shell
# variables and are cleared as soon as their respective installation step is complete.
read_secret_into INSTALL_LUKS_PASSPHRASE "$LUKS_PASSPHRASE_FILE" "LUKS passphrase" true
read_secret_into INSTALL_USER_PASSWORD "$USER_PASSWORD_FILE" "Password for $USERNAME" true

prepare_disk
install_base_system
configure_base_system
create_efi_boot_entry

sync
cleanup_target
INSTALL_COMPLETED=true
trap - EXIT

cat <<EOF

Installation completed successfully.

Next steps:
  1. Reboot and remove the Arch installation media.
  2. Unlock LUKS with the passphrase and log in as $USERNAME.
  3. Run: archctl provision
  4. Run: sudo archctl secure-boot
  5. Reboot with Secure Boot enabled, then run: sudo archctl tpm-enroll
  6. Run: sudo archctl verify

The installed copy of this repository is /opt/arch-workstation.
EOF
