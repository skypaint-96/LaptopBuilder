#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

require_non_root
require_commands git makepkg sudo
load_config "$CONFIG_FILE"
validate_config runtime
bool_true "$ENABLE_AUR" || exit 0

bootstrap_aur_helper() {
  command -v "$AUR_HELPER" >/dev/null 2>&1 && return 0

  local package=$AUR_HELPER_PACKAGE temp_dir
  local -a pacman_args makepkg_args
  info "Bootstrapping the '$package' AUR package to provide the '$AUR_HELPER' command."

  if [[ $package == paru ]]; then
    info "Installing the explicit Rust provider first so makepkg cannot open a cargo provider menu."
    pacman_args=(-S --needed rust)
    bool_true "$PROVISION_NONINTERACTIVE" && pacman_args+=(--noconfirm)
    sudo pacman "${pacman_args[@]}"
  fi

  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT
  git clone --depth 1 "https://aur.archlinux.org/${package}.git" "$temp_dir/$package"

  if bool_true "$AUR_NONINTERACTIVE"; then
    warn "Automated AUR mode is enabled; only packages in AUR_PACKAGES are built, but PKGBUILD review is skipped."
  else
    printf '\n----- %s PKGBUILD -----\n' "$package"
    cat "$temp_dir/$package/PKGBUILD"
    if [[ -r $temp_dir/$package/.SRCINFO ]]; then
      printf '\n----- %s .SRCINFO -----\n' "$package"
      cat "$temp_dir/$package/.SRCINFO"
    fi
    confirm "Build and install $package?" no || die "$package bootstrap cancelled."
  fi

  (
    cd "$temp_dir/$package" || exit 1
    makepkg_args=(--syncdeps --install --needed --cleanbuild --clean)
    if bool_true "$AUR_NONINTERACTIVE"; then
      makepkg_args+=(--noconfirm)
    fi
    makepkg "${makepkg_args[@]}"
  )

  rm -rf "$temp_dir"
  trap - EXIT
  command -v "$AUR_HELPER" >/dev/null 2>&1 \
    || die "$package completed without installing the '$AUR_HELPER' command."
}

bootstrap_aur_helper

declare -a packages helper_args
read -r -a packages <<< "$AUR_PACKAGES"
((${#packages[@]} > 0)) || exit 0

info "Installing configured AUR allow-list: ${packages[*]}"
helper_args=(-S --needed)
if bool_true "$AUR_NONINTERACTIVE"; then
  helper_args+=(--noconfirm --skipreview)
fi
"$AUR_HELPER" "${helper_args[@]}" "${packages[@]}"
