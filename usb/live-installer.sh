#!/usr/bin/env bash
set -Eeuo pipefail

USB_ROOT="${MASON_USB_ROOT:-}"
REPO_ROOT=""
INSTALL_CONFIG=""

usage() {
  cat <<'USAGE'
Usage: ./usb/live-installer.sh --usb-root PATH --repo-root PATH --install-config PATH
USAGE
}

while (($#)); do
  case "$1" in
    --usb-root) [[ $# -ge 2 ]] || { echo '--usb-root requires a path' >&2; exit 2; }; USB_ROOT=$2; shift 2 ;;
    --repo-root) [[ $# -ge 2 ]] || { echo '--repo-root requires a path' >&2; exit 2; }; REPO_ROOT=$2; shift 2 ;;
    --install-config) [[ $# -ge 2 ]] || { echo '--install-config requires a path' >&2; exit 2; }; INSTALL_CONFIG=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n $REPO_ROOT ]] || REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/usb-common.sh
source "$REPO_ROOT/usb/lib/usb-common.sh"

require_root
[[ -n $USB_ROOT ]] || USB_ROOT=$(usb_find_root) || usb_die "Installer USB not found."
usb_verify_layout "$USB_ROOT" || usb_die "Invalid installer USB layout: $USB_ROOT"
[[ -r $INSTALL_CONFIG ]] || usb_die "Install configuration not found: $INSTALL_CONFIG"
LAYOUT=$(usb_layout_dir "$USB_ROOT")
usb_load_config "$LAYOUT/config/usb.conf"
load_config "$INSTALL_CONFIG"
validate_config install

current_slot=$(usb_current_arch_slot || usb_read_active_slot "$USB_ROOT")
current_version=$(tr -d '\r\n' < "$USB_ROOT/arch-$current_slot/version" 2>/dev/null || printf unknown)

network_status() {
  if usb_network_available; then
    printf 'online\n'
  else
    printf 'offline\n'
  fi
}

print_banner() {
  printf '\033c'
  cat <<EOF_BANNER
============================================================
 Mason's Arch workstation installer
============================================================
Live Arch       : $current_version (slot $current_slot)
Repository      : ${MASON_REPO_SOURCE:-local USB snapshot} @ ${MASON_REPO_COMMIT:-unknown}
Machine profile : ${MASON_INSTALL_CONFIG_SOURCE:-$INSTALL_CONFIG}
Target          : $DISK
Host / user     : $HOSTNAME / $USERNAME
Network         : $(network_status)
Offline cache   : $(if [[ -d $LAYOUT/cache/pacman ]]; then printf official; else printf absent; fi)$(if [[ -d $LAYOUT/cache/aur ]]; then printf ' + AUR'; fi)
USB writable    : ${MASON_USB_WRITABLE:-unknown}
============================================================
EOF_BANNER
}

refresh_arch_cache() {
  local rc
  set +e
  bash "$REPO_ROOT/usb/refresh-arch.sh" --usb-root "$USB_ROOT" --if-newer
  rc=$?
  set -e
  case "$rc" in
    0) return 0 ;;
    10)
      usb_warn "A fresher Arch live environment is ready for the next boot."
      if usb_ask_yes_no "Reboot now and continue from the refreshed slot?" yes; then
        sync
        reboot
        exit 0
      fi
      return 0
      ;;
    *) usb_warn "Arch cache refresh failed with status $rc; the current and recovery slots were left available."; return "$rc" ;;
  esac
}

refresh_package_cache() {
  local -a args=(--usb-root "$USB_ROOT" --install-config "$INSTALL_CONFIG")
  if ! bool_true "$ENABLE_AUR" || ! usb_policy_allows "$AUR_CACHE_UPDATE_POLICY" "Build reviewed AUR packages into the offline cache?"; then
    args+=(--official-only)
  fi
  bash "$REPO_ROOT/usb/refresh-packages.sh" "${args[@]}"
}

write_runtime_config() {
  local mode=$1 output=$2 aur_path=""
  cp "$INSTALL_CONFIG" "$output"
  if bool_true "$ENABLE_AUR"; then
    aur_path="$LAYOUT/cache/aur"
  fi
  {
    printf '\n# Runtime source selection written by the installer USB.\n'
    printf 'INSTALL_SOURCE_MODE=%q\n' "$mode"
    printf 'OFFLINE_REPO_PATH=%q\n' "$LAYOUT/cache/pacman"
    printf 'OFFLINE_AUR_REPO_PATH=%q\n' "$aur_path"
    printf 'NETWORK_CHECK_URL=%q\n' "$NETWORK_CHECK_URL"
  } >> "$output"
  chmod 0600 "$output"
}

run_install() {
  local mode=$1 runtime_config=/run/mason-installer/install.runtime.conf
  write_runtime_config "$mode" "$runtime_config"
  printf '\n'
  case "$mode" in
    auto) usb_info "Online-first mode selected: current Arch repositories will be used when reachable, otherwise the complete USB cache is used." ;;
    offline) usb_info "Strict offline mode selected: no package download will be attempted." ;;
  esac
  bash "$REPO_ROOT/install.sh" --config "$runtime_config"
  printf '\n'
  usb_ok "Target installation completed."
  if usb_ask_yes_no "Reboot into the installed system now?" yes; then
    sync
    reboot
  fi
}

# Online-first boot behaviour: use the downloaded repository immediately, and
# stage a fresher official Arch image into the non-running slot for a safe reboot.
if [[ ${MASON_USB_WRITABLE:-true} == true ]] \
  && usb_network_available \
  && usb_policy_allows "$ARCH_UPDATE_POLICY" "Check and stage the latest official Arch live image?"; then
  refresh_arch_cache || true
fi

while true; do
  print_banner
  cat <<'EOF_MENU'
1) Install Arch - online first, verified USB package fallback
2) Install Arch - force fully offline cache
3) Refresh the cached Arch live image
4) Refresh the complete offline package cache
5) Verify the USB and both recovery generations
6) Configure Wi-Fi with iwctl
7) Open a maintenance shell
8) Reboot
9) Power off
EOF_MENU
  read -r -p 'Selection: ' selection
  case "$selection" in
    1) run_install auto ;;
    2) run_install offline ;;
    3)
      [[ ${MASON_USB_WRITABLE:-true} == true ]] \
        || { usb_warn "The USB is read-only; refresh is unavailable."; sleep 2; continue; }
      usb_network_available || { usb_warn "Connect to the internet first."; sleep 2; continue; }
      refresh_arch_cache || true
      ;;
    4)
      [[ ${MASON_USB_WRITABLE:-true} == true ]] \
        || { usb_warn "The USB is read-only; refresh is unavailable."; sleep 2; continue; }
      usb_network_available || { usb_warn "Connect to the internet first."; sleep 2; continue; }
      if usb_policy_allows "$PACKAGE_CACHE_UPDATE_POLICY" "Refresh the offline package cache?"; then
        refresh_package_cache
      else
        usb_warn "Package-cache refresh was declined by policy or prompt."
      fi
      read -r -p 'Press Enter to return to the menu.' _
      ;;
    5)
      bash "$REPO_ROOT/usb/verify-usb.sh" --usb-root "$USB_ROOT"
      read -r -p 'Press Enter to return to the menu.' _
      ;;
    6)
      command -v iwctl >/dev/null 2>&1 || usb_die "iwctl is unavailable in this live image."
      iwctl
      ;;
    7)
      usb_info "Exit the shell to return to the installer."
      bash --noprofile --norc
      ;;
    8) sync; reboot ;;
    9) sync; poweroff ;;
    *) usb_warn "Choose a number from 1 to 9."; sleep 1 ;;
  esac
done
