#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

ASSUME_YES=false
REBOOT_FIRMWARE=false
SKIP_UPGRADE=false

usage() {
  cat <<'EOF'
Usage: archctl finish [options]

Resumes the first-boot workflow from its current state. It can be safely rerun.

Options:
  --yes               Skip the Secure Boot key-enrollment confirmation
  --reboot-firmware   Reboot directly into firmware setup when that is the next step
  --skip-upgrade      Skip the full package upgrade during provisioning
EOF
}

while (($#)); do
  case "$1" in
    --yes)
      ASSUME_YES=true
      shift
      ;;
    --reboot-firmware)
      REBOOT_FIRMWARE=true
      shift
      ;;
    --skip-upgrade)
      SKIP_UPGRADE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown finish option: $1"
      ;;
  esac
done

require_non_root
require_commands sudo
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run archctl finish as configured user '$USERNAME'."

trap stop_sudo_keepalive EXIT
info "Opening one sudo session for the resumable first-boot workflow."
start_sudo_keepalive

root_env=(
  env
  "ARCH_WORKSTATION_ROOT=$REPO_ROOT"
  "ARCH_WORKSTATION_CONFIG=$CONFIG_FILE"
)

get_stage() {
  sudo "${root_env[@]}" "$REPO_ROOT/scripts/security/status.sh" --stage
}

for _ in {1..8}; do
  stage=$(get_stage)
  info "Detected setup stage: $stage"

  case "$stage" in
    provision)
      provision_args=()
      bool_true "$SKIP_UPGRADE" && provision_args+=(--skip-upgrade)
      "$REPO_ROOT/scripts/provision.sh" "${provision_args[@]}"
      ;;

    firmware-setup-mode)
      cat <<'EOF'

Firmware action required before owner keys can be enrolled:
  1. Reboot to firmware setup.
  2. Keep Secure Boot disabled.
  3. Clear the enrolled Secure Boot keys / reset to Setup Mode.
  4. Do not restore factory keys.
  5. Boot Arch and run: archctl finish
EOF
      if bool_true "$REBOOT_FIRMWARE"; then
        if ! sudo systemctl reboot --firmware-setup; then
          warn "The firmware-setup reboot request was not supported. Reboot normally and enter firmware setup manually."
        fi
      fi
      exit 0
      ;;

    prepare-secure-boot)
      security_args=()
      bool_true "$ASSUME_YES" && security_args+=(--yes)
      sudo "${root_env[@]}" "$REPO_ROOT/scripts/security/secure-boot.sh" "${security_args[@]}"
      ;;

    enable-secure-boot)
      cat <<'EOF'

Firmware action required:
  1. Reboot to firmware setup.
  2. Enable Secure Boot.
  3. Do not clear keys and do not restore factory keys.
  4. Boot Arch and run: archctl finish
EOF
      if bool_true "$REBOOT_FIRMWARE"; then
        if ! sudo systemctl reboot --firmware-setup; then
          warn "The firmware-setup reboot request was not supported. Reboot normally and enter firmware setup manually."
        fi
      fi
      exit 0
      ;;

    enroll-tpm)
      sudo "${root_env[@]}" "$REPO_ROOT/scripts/security/tpm-enroll.sh"
      ;;

    complete)
      sudo "${root_env[@]}" "$REPO_ROOT/scripts/security/verify.sh"
      sudo install -d -m 0755 "$STATE_DIR"
      printf '%s\n' "$(date --iso-8601=seconds)" | sudo tee "$STATE_DIR/complete" >/dev/null
      success "Workstation setup is complete. Use 'archctl update' for maintenance and 'archctl auth' for application sign-ins."
      exit 0
      ;;

    *)
      die "Unknown setup stage returned by status checker: $stage"
      ;;
  esac
done

die "The first-boot workflow did not converge after eight stage transitions. Run 'archctl status' for diagnostics."
