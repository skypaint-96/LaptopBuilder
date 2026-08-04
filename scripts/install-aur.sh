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
  local package=$AUR_HELPER_PACKAGE temp_dir candidate
  local -a pacman_args makepkg_args installed_helpers=()

  helper_matches_policy() {
    command -v "$AUR_HELPER" >/dev/null 2>&1 || return 1
    "$AUR_HELPER" --version >/dev/null 2>&1 || return 1
    case "$package" in
      paru) pacman -Q paru >/dev/null 2>&1 \
        && ! pacman -Q paru-bin >/dev/null 2>&1 \
        && ! pacman -Q paru-bin-debug >/dev/null 2>&1 ;;
      paru-bin) pacman -Q paru-bin >/dev/null 2>&1 ;;
    esac
  }

  if helper_matches_policy; then
    return 0
  fi

  if command -v "$AUR_HELPER" >/dev/null 2>&1; then
    warn "The installed '$AUR_HELPER' is broken or does not match AUR_HELPER_PACKAGE=$package; rebuilding it."
  fi

  for candidate in paru paru-debug paru-bin paru-bin-debug; do
    pacman -Q "$candidate" >/dev/null 2>&1 && installed_helpers+=("$candidate")
  done
  if ((${#installed_helpers[@]})); then
    pacman_args=(-Rns)
    bool_true "$PROVISION_NONINTERACTIVE" && pacman_args+=(--noconfirm)
    sudo pacman "${pacman_args[@]}" "${installed_helpers[@]}"
  fi

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
  helper_matches_policy \
    || die "$package completed without installing a working '$AUR_HELPER' command."
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
