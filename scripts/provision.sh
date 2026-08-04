#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
SKIP_UPGRADE=false

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

usage() {
  cat <<'EOF'
Usage: archctl apply [--skip-upgrade]
       archctl provision [--skip-upgrade]

Applies the system and user configuration. Run it as the configured normal user;
it opens one sudo session and keeps that session alive for the whole operation.
EOF
}

while (($#)); do
  case "$1" in
    --skip-upgrade)
      SKIP_UPGRADE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown provision option: $1"
      ;;
  esac
done

require_non_root
require_commands ansible-playbook findmnt pacman sudo
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run provisioning as configured user '$USERNAME', not '$(id -un)'."

trap stop_sudo_keepalive EXIT
info "Opening one sudo session for the complete provisioning run."
start_sudo_keepalive

findmnt -rn /efi >/dev/null 2>&1 \
  || die "/efi is not mounted; refusing to update kernels or boot assets."
if secure_boot_enabled; then
  require_commands sbctl
  sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem \
    || die "Secure Boot is active but the sbctl db key pair is unavailable; refusing to provision."
  sudo test -r /etc/kernel/uki.conf \
    || die "Secure Boot is active but /etc/kernel/uki.conf is missing; refusing to provision."
fi

if ! bool_true "$SKIP_UPGRADE"; then
  info "Synchronising package databases and applying a full Arch upgrade."
  declare -a pacman_args=(-Syu --needed)
  if bool_true "$PROVISION_NONINTERACTIVE"; then
    pacman_args+=(--noconfirm)
  fi
  sudo pacman "${pacman_args[@]}"
fi

info "Applying idempotent Ansible roles as root through the existing sudo session."
declare -a ansible_args=(
  -i "$REPO_ROOT/ansible/inventory.ini"
  "$REPO_ROOT/ansible/site.yml"
  --extra-vars "arch_user=$USERNAME"
  --extra-vars "workstation_repo_root=$REPO_ROOT"
  --extra-vars "console_keymap=$KEYMAP"
  --extra-vars "x11_layout=$X11_LAYOUT"
  --extra-vars "enable_ssh=$ENABLE_SSH"
  --extra-vars "enable_onedrive=$ENABLE_ONEDRIVE"
  --extra-vars "onedrive_sync_dir=$ONEDRIVE_SYNC_DIR"
  --extra-vars "onedrive_link_dirs=$ONEDRIVE_LINK_DIRS"
  --extra-vars "onedrive_skip_dotfiles=$ONEDRIVE_SKIP_DOTFILES"
  --extra-vars "onedrive_skip_symlinks=$ONEDRIVE_SKIP_SYMLINKS"
  --extra-vars "onedrive_use_recycle_bin=$ONEDRIVE_USE_RECYCLE_BIN"
  --extra-vars "onedrive_enable_service=$ONEDRIVE_ENABLE_SERVICE"
  --extra-vars "enable_first_login_auth=$ENABLE_FIRST_LOGIN_AUTH"
  --extra-vars "auth_github_cli=$AUTH_GITHUB_CLI"
  --extra-vars "github_git_protocol=$GITHUB_GIT_PROTOCOL"
  --extra-vars "auth_onedrive=$AUTH_ONEDRIVE"
  --extra-vars "auth_vscode=$AUTH_VSCODE"
  --extra-vars "auth_edge=$AUTH_EDGE"
  --extra-vars "auth_steam=$AUTH_STEAM"
  --extra-vars "enable_docker=$ENABLE_DOCKER"
  --extra-vars "docker_add_user_to_group=$DOCKER_ADD_USER_TO_GROUP"
  --extra-vars "enable_gaming=$ENABLE_GAMING"
  --extra-vars "gpu_vendor=$GPU_VENDOR"
  --extra-vars "enable_snapshots=$ENABLE_SNAPSHOTS"
  --extra-vars "enable_t480=$ENABLE_T480"
  --extra-vars "t480_battery_thresholds=$T480_BATTERY_THRESHOLDS"
  --extra-vars "t480_start_charge=$T480_START_CHARGE"
  --extra-vars "t480_stop_charge=$T480_STOP_CHARGE"
)
sudo env ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg" \
  ansible-playbook "${ansible_args[@]}"

if bool_true "$ENABLE_AUR"; then
  "$REPO_ROOT/scripts/install-aur.sh"
fi

if bool_true "$INSTALL_VSCODE_EXTENSIONS"; then
  "$REPO_ROOT/scripts/configure-vscode.sh"
fi

if bool_true "$ENABLE_POWERSHELL_PROFILE"; then
  require_commands pwsh
  declare -a pwsh_args=(-NoLogo -NoProfile -File "$REPO_ROOT/powershell/Configure-Workstation.ps1")
  if bool_true "$INSTALL_POWERSHELL_MODULES"; then
    pwsh_args+=(-InstallModules)
  fi
  pwsh "${pwsh_args[@]}"
fi

# Package transactions may replace systemd-boot or regenerate UKIs. Enforce the
# complete signed set before marking provisioning complete whenever keys exist.
if bool_true "$ENABLE_SECURE_BOOT" \
  && sudo test -r /var/lib/sbctl/keys/db/db.key \
  && sudo test -r /var/lib/sbctl/keys/db/db.pem; then
  info "Rebuilding and verifying the signed boot chain after provisioning."
  sudo env \
    "ARCH_WORKSTATION_ROOT=$REPO_ROOT" \
    "ARCH_WORKSTATION_CONFIG=$CONFIG_FILE" \
    "$REPO_ROOT/scripts/security/secure-boot.sh" --yes --sign-only
fi

sudo install -d -m 0755 "$STATE_DIR"
printf '%s\n' "$(date --iso-8601=seconds)" | sudo tee "$STATE_DIR/provisioned" >/dev/null
success "Provisioning completed."
if bool_true "$ENABLE_FIRST_LOGIN_AUTH"; then
  echo "Supported application sign-ins will be offered at the next graphical login; rerun them with: archctl auth"
fi
if bool_true "$DOCKER_ADD_USER_TO_GROUP"; then
  echo "Docker group membership takes effect after the next login or reboot."
fi
