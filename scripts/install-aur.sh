#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

require_non_root
load_config "$CONFIG_FILE"
validate_config runtime
bool_true "$ENABLE_AUR" || exit 0

read -r -a packages <<< "$AUR_PACKAGES"
all_applications_installed=true
for package in "${packages[@]}"; do
  pacman -Q "$package" >/dev/null 2>&1 || all_applications_installed=false
done

if command -v "$AUR_HELPER" >/dev/null 2>&1 && bool_true "$all_applications_installed"; then
  success "The AUR helper and configured AUR applications are already installed."
  exit 0
fi

require_commands git makepkg sudo
if ! command -v "$AUR_HELPER" >/dev/null 2>&1; then
  info "Bootstrapping $AUR_HELPER from the reviewed $AUR_HELPER_PACKAGE AUR build."
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT
  git clone --depth 1 "https://aur.archlinux.org/$AUR_HELPER_PACKAGE.git" "$temp_dir/$AUR_HELPER_PACKAGE"
  if bool_true "$AUR_NONINTERACTIVE"; then
    warn "AUR_NONINTERACTIVE also bypasses review of the $AUR_HELPER_PACKAGE bootstrap PKGBUILD."
  else
    printf '\n----- %s PKGBUILD -----\n' "$AUR_HELPER_PACKAGE"
    cat "$temp_dir/$AUR_HELPER_PACKAGE/PKGBUILD"
    if [[ -r $temp_dir/$AUR_HELPER_PACKAGE/.SRCINFO ]]; then
      printf '\n----- %s .SRCINFO -----\n' "$AUR_HELPER_PACKAGE"
      cat "$temp_dir/$AUR_HELPER_PACKAGE/.SRCINFO"
    fi
    printf '\nType BUILD PARU to continue: '
    read -r bootstrap_confirmation
    [[ $bootstrap_confirmation == 'BUILD PARU' ]] || die "$AUR_HELPER bootstrap cancelled."
  fi
  (
    cd "$temp_dir/$AUR_HELPER_PACKAGE"
    makepkg_args=(--syncdeps --install --needed)
    if bool_true "$AUR_NONINTERACTIVE"; then
      makepkg_args+=(--noconfirm)
    fi
    makepkg "${makepkg_args[@]}"
  )
  rm -rf "$temp_dir"
  trap - EXIT
  command -v "$AUR_HELPER" >/dev/null 2>&1 \
    || die "$AUR_HELPER_PACKAGE installed without providing the expected $AUR_HELPER command."
fi

((${#packages[@]} > 0)) || {
  success "AUR helper installed; no additional AUR applications are configured."
  exit 0
}

info "Installing configured AUR packages: ${packages[*]}"
if bool_true "$AUR_NONINTERACTIVE"; then
  warn "AUR_NONINTERACTIVE bypasses the normal build-file review."
  "$AUR_HELPER" -S --needed --noconfirm --skipreview "${packages[@]}"
else
  "$AUR_HELPER" -S --needed "${packages[@]}"
fi
