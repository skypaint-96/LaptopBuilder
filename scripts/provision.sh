#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/install-source.sh
source "$REPO_ROOT/scripts/lib/install-source.sh"
# shellcheck source=lib/packages.sh
source "$REPO_ROOT/scripts/lib/packages.sh"

require_non_root
require_commands ansible-playbook curl findmnt pacman sudo
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run provisioning as configured user '$USERNAME', not '$(id -un)'."

info "Refreshing sudo credentials."
sudo -v
findmnt -rn /efi >/dev/null 2>&1 \
  || die "/efi is not mounted; refusing to alter a workstation with missing boot assets."

ONLINE_NOW=false
if network_available; then ONLINE_NOW=true; fi
collect_official_packages configured_official_packages
if bool_true "$ONLINE_NOW"; then
  if secure_boot_enabled; then
    require_commands sbctl
    sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem \
      || die "Secure Boot is active but the sbctl db key pair is unavailable; refusing to update."
    sudo test -r /etc/kernel/uki.conf \
      || die "Secure Boot is active but /etc/kernel/uki.conf is missing; refusing to update."
  fi
  info "Internet is available; applying a full Arch upgrade and current configured package policy."
  sudo pacman -Syu --needed "${configured_official_packages[@]}"
else
  missing_official_packages=()
  sudo test -r /etc/arch-installer/official-packages-preinstalled \
    || die "No network is available and this installation lacks the complete preinstalled package marker."
  for package in "${configured_official_packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing_official_packages+=("$package")
  done
  ((${#missing_official_packages[@]} == 0)) \
    || die "No network is available and configured packages are missing: ${missing_official_packages[*]}. Connect once or rebuild the USB package cache."
  warn "No internet is available; package upgrades and network-only user extensions are being skipped."
fi

info "Applying idempotent Ansible roles."
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"
ansible-playbook \
  -i "$REPO_ROOT/ansible/inventory.ini" \
  "$REPO_ROOT/ansible/site.yml" \
  --extra-vars "arch_user=$USERNAME" \
  --extra-vars "workstation_repo_root=$REPO_ROOT" \
  --extra-vars "packages_preinstalled=true" \
  --extra-vars "enable_docker=$ENABLE_DOCKER" \
  --extra-vars "docker_add_user_to_group=$DOCKER_ADD_USER_TO_GROUP" \
  --extra-vars "enable_gaming=$ENABLE_GAMING" \
  --extra-vars "gpu_vendor=$GPU_VENDOR" \
  --extra-vars "enable_snapshots=$ENABLE_SNAPSHOTS" \
  --extra-vars "enable_t480=$ENABLE_T480" \
  --extra-vars "t480_battery_thresholds=$T480_BATTERY_THRESHOLDS" \
  --extra-vars "t480_start_charge=$T480_START_CHARGE" \
  --extra-vars "t480_stop_charge=$T480_STOP_CHARGE"

if bool_true "$ENABLE_AUR"; then
  if bool_true "$ONLINE_NOW" || sudo test -r /etc/arch-installer/aur-packages-preinstalled; then
    "$REPO_ROOT/scripts/install-aur.sh"
  else
    die "Configured AUR packages were neither cached during installation nor reachable online."
  fi
fi

if bool_true "$INSTALL_VSCODE_EXTENSIONS"; then
  "$REPO_ROOT/scripts/configure-vscode.sh"
fi

if bool_true "$ENABLE_POWERSHELL_PROFILE"; then
  require_commands pwsh
  pwsh_args=(-NoLogo -NoProfile -File "$REPO_ROOT/powershell/Configure-Workstation.ps1")
  if bool_true "$INSTALL_POWERSHELL_MODULES" && bool_true "$ONLINE_NOW"; then
    pwsh_args+=(-InstallModules)
  elif bool_true "$INSTALL_POWERSHELL_MODULES"; then
    warn "PowerShell Gallery modules were requested but skipped while offline."
  fi
  pwsh "${pwsh_args[@]}"
fi

success "Provisioning completed."
if bool_true "$DOCKER_ADD_USER_TO_GROUP"; then
  echo "Log out and back in before relying on new Docker group membership."
fi
