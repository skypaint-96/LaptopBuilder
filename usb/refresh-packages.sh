#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/packages.sh
source "$REPO_ROOT/scripts/lib/packages.sh"
# shellcheck source=lib/usb-common.sh
source "$REPO_ROOT/usb/lib/usb-common.sh"

USB_ROOT="${MASON_USB_ROOT:-}"
INSTALL_CONFIG="$REPO_ROOT/config/install.conf"
WITH_AUR=true

usage() {
  cat <<'USAGE'
Usage: sudo ./usb/refresh-packages.sh --usb-root PATH --install-config PATH [options]

Options:
  --official-only   Cache only official Arch packages
  -h, --help        Show this help

Creates a dependency-complete local pacman repository. AUR build files are
printed and require explicit confirmation unless AUR_NONINTERACTIVE=true.
The previous complete cache remains in place until the new pair verifies.
USAGE
}

while (($#)); do
  case "$1" in
    --usb-root) [[ $# -ge 2 ]] || usb_die "--usb-root requires a path"; USB_ROOT=$2; shift 2 ;;
    --install-config) [[ $# -ge 2 ]] || usb_die "--install-config requires a path"; INSTALL_CONFIG=$2; shift 2 ;;
    --official-only) WITH_AUR=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usb_die "Unknown option: $1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || usb_die "Package-cache refresh must run as root."
[[ -n $USB_ROOT ]] || USB_ROOT=$(usb_find_root) || usb_die "Installer USB not found."
usb_verify_layout "$USB_ROOT" || usb_die "Invalid installer USB layout: $USB_ROOT"
[[ -r $INSTALL_CONFIG ]] || usb_die "Install configuration not found: $INSTALL_CONFIG"

load_config "$INSTALL_CONFIG"
validate_config runtime
LAYOUT=$(usb_layout_dir "$USB_ROOT")
usb_load_config "$LAYOUT/config/usb.conf"
usb_require_commands bsdtar curl df pacman repo-add runuser sha256sum sudo useradd userdel
usb_remount_rw "$USB_ROOT"
usb_recover_interrupted_updates "$USB_ROOT"
usb_network_available || usb_die "An internet connection is required to refresh package caches."

free_mib=$(df -Pm "$USB_ROOT" | awk 'NR == 2 {print $4}')
((free_mib >= PACKAGE_CACHE_MIN_FREE_MIB)) \
  || usb_die "Package-cache staging requires at least ${PACKAGE_CACHE_MIN_FREE_MIB} MiB free; only ${free_mib} MiB is available."

CACHE_ROOT="$LAYOUT/cache"
OFFICIAL_STAGE="$CACHE_ROOT/pacman.new"
AUR_STAGE="$CACHE_ROOT/aur.new"
AUR_DEPENDENCIES=()
AUR_STAGE_PRESENT=false
mkdir -p "$CACHE_ROOT"
rm -rf "$OFFICIAL_STAGE" "$AUR_STAGE"

cleanup_stages() {
  rm -rf "$OFFICIAL_STAGE" "$AUR_STAGE"
}
trap cleanup_stages EXIT

write_manifest() {
  local directory=$1
  (
    cd "$directory"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' \
      | LC_ALL=C sort -z \
      | xargs -0 -r sha256sum > SHA256SUMS
    sha256sum --check --quiet SHA256SUMS
  )
}

activate_cache_pair() {
  local official_current="$CACHE_ROOT/pacman"
  local aur_current="$CACHE_ROOT/aur"
  local official_old="$CACHE_ROOT/pacman.old"
  local aur_old="$CACHE_ROOT/aur.old"
  local failed=false

  rm -rf "$official_old" "$aur_old"
  [[ ! -e $official_current ]] || mv "$official_current" "$official_old"
  [[ ! -e $aur_current ]] || mv "$aur_current" "$aur_old"

  if ! mv "$OFFICIAL_STAGE" "$official_current"; then failed=true; fi
  if ! usb_bool_true "$failed" && usb_bool_true "$AUR_STAGE_PRESENT"; then
    if ! mv "$AUR_STAGE" "$aur_current"; then failed=true; fi
  fi
  if ! usb_bool_true "$failed" && ! usb_verify_directory_manifest "$official_current"; then failed=true; fi
  if ! usb_bool_true "$failed" && usb_bool_true "$AUR_STAGE_PRESENT" \
    && ! usb_verify_directory_manifest "$aur_current"; then failed=true; fi

  if usb_bool_true "$failed"; then
    rm -rf "$official_current" "$aur_current"
    [[ ! -e $official_old ]] || mv "$official_old" "$official_current"
    [[ ! -e $aur_old ]] || mv "$aur_old" "$aur_current"
    sync
    usb_die "New package-cache generation failed activation; the previous generation was restored."
  fi

  # Flush the activated generation before deleting the rollback copy. This
  # makes an interrupted FAT update recoverable through the .old directories.
  sync
  rm -rf "$official_old" "$aur_old"
  sync
}

validate_staged_cache_pair() {
  local -a requested
  local pacman_config db_path

  [[ $OFFICIAL_STAGE != *[[:space:]]* ]] \
    || usb_die "Package-cache staging paths must not contain whitespace: $OFFICIAL_STAGE"
  if usb_bool_true "$AUR_STAGE_PRESENT"; then
    [[ $AUR_STAGE != *[[:space:]]* ]] \
      || usb_die "Package-cache staging paths must not contain whitespace: $AUR_STAGE"
    collect_all_requested_packages requested
  else
    collect_official_packages requested
  fi

  pacman_config=$(mktemp)
  db_path=$(mktemp -d)
  mkdir -p "$db_path/local"
  cat > "$pacman_config" <<EOF_CONFIG
[options]
Architecture = auto
CheckSpace
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional

EOF_CONFIG
  if usb_bool_true "$AUR_STAGE_PRESENT"; then
    cat >> "$pacman_config" <<EOF_CONFIG
[workstation-aur]
SigLevel = Optional TrustAll
Server = file://$AUR_STAGE

EOF_CONFIG
  fi
  cat >> "$pacman_config" <<EOF_CONFIG
[workstation]
SigLevel = Optional TrustAll
Server = file://$OFFICIAL_STAGE
EOF_CONFIG

  if ! pacman --config "$pacman_config" --dbpath "$db_path" \
      --sync --refresh --noconfirm >/dev/null; then
    rm -rf "$db_path" "$pacman_config"
    usb_die "The staged package repository databases could not be loaded."
  fi
  if ! pacman --config "$pacman_config" --dbpath "$db_path" \
      --sync --print --print-format '%n' "${requested[@]}" >/dev/null; then
    rm -rf "$db_path" "$pacman_config"
    usb_die "The staged cache does not contain the complete dependency closure for the configured workstation."
  fi
  rm -rf "$db_path" "$pacman_config"
  usb_ok "The staged package repositories resolve every configured package and dependency."
}

build_aur_stage() {
  local -a aur_packages before after built_packages
  local build_root build_user sudoers_file package checkout confirmation pkg_file db_temp
  collect_aur_packages aur_packages
  ((${#aur_packages[@]} > 0)) || return 0

  mkdir -p "$AUR_STAGE"
  build_root=$(mktemp -d)
  build_user="masonaur$$"
  sudoers_file="/etc/sudoers.d/90-$build_user"

  # Git and base-devel are intentionally installed only into the disposable
  # live session when the stock Arch image does not already provide them.
  pacman -Syu --needed --noconfirm base-devel git sudo
  usb_require_commands git makepkg

  if id "$build_user" >/dev/null 2>&1; then
    userdel -r "$build_user" >/dev/null 2>&1 || true
  fi
  useradd --create-home --shell /bin/bash "$build_user"
  chmod 0755 "$build_root"
  printf '%s ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman\n' "$build_user" > "$sudoers_file"
  chmod 0440 "$sudoers_file"
  mapfile -t before < <(pacman -Qq | LC_ALL=C sort)

  cleanup_aur_builder() {
    rm -f "$sudoers_file"
    userdel -r "$build_user" >/dev/null 2>&1 || true
    rm -rf "$build_root"
  }
  trap 'cleanup_aur_builder; cleanup_stages' EXIT

  for package in "${aur_packages[@]}"; do
    checkout="$build_root/$package"
    usb_info "Downloading AUR build files for $package."
    git clone --quiet --depth 1 "https://aur.archlinux.org/$package.git" "$checkout"
    printf '\n----- %s/PKGBUILD -----\n' "$package"
    cat "$checkout/PKGBUILD"
    if [[ -r $checkout/.SRCINFO ]]; then
      printf '\n----- %s/.SRCINFO -----\n' "$package"
      cat "$checkout/.SRCINFO"
    fi

    if ! bool_true "$AUR_NONINTERACTIVE"; then
      read -r -p "Type 'BUILD $package' to build and cache it: " confirmation
      [[ $confirmation == "BUILD $package" ]] || usb_die "AUR cache refresh cancelled."
    else
      usb_warn "AUR_NONINTERACTIVE=true: build-file review confirmation is bypassed."
    fi

    chown -R "$build_user:$build_user" "$checkout"
    runuser -u "$build_user" -- env HOME="/home/$build_user" bash -lc \
      "cd '$checkout' && makepkg --syncdeps --cleanbuild --noconfirm"
    while IFS= read -r pkg_file; do
      [[ -f $pkg_file ]] || continue
      cp -f "$pkg_file" "$AUR_STAGE/"
    done < <(runuser -u "$build_user" -- env HOME="/home/$build_user" bash -lc "cd '$checkout' && makepkg --packagelist")
  done

  mapfile -t after < <(pacman -Qq | LC_ALL=C sort)
  mapfile -t AUR_DEPENDENCIES < <(comm -13 <(printf '%s\n' "${before[@]}") <(printf '%s\n' "${after[@]}"))

  mapfile -t built_packages < <(find "$AUR_STAGE" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' -print | LC_ALL=C sort)
  ((${#built_packages[@]} > 0)) || usb_die "No AUR package files were produced."
  db_temp=$(mktemp -d)
  repo-add -q "$db_temp/workstation-aur.db.tar.gz" "${built_packages[@]}"
  cp "$db_temp/workstation-aur.db.tar.gz" "$AUR_STAGE/workstation-aur.db"
  rm -rf "$db_temp"
  printf '%s\n' "${aur_packages[@]}" > "$AUR_STAGE/packages.requested.txt"
  write_manifest "$AUR_STAGE"
  AUR_STAGE_PRESENT=true

  trap cleanup_stages EXIT
  cleanup_aur_builder
  usb_ok "AUR package cache staged."
}

build_official_stage() {
  local -a packages package_files
  local online_config db_path db_temp
  collect_official_packages packages
  packages+=("${AUR_DEPENDENCIES[@]}")
  mapfile -t packages < <(printf '%s\n' "${packages[@]}" | awk 'NF' | LC_ALL=C sort -u)

  mkdir -p "$OFFICIAL_STAGE"
  online_config=$(mktemp)
  cat > "$online_config" <<'EOF_CONFIG'
[options]
Architecture = auto
CheckSpace
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF_CONFIG
  db_path=$(mktemp -d)
  mkdir -p "$db_path/local"

  usb_info "Downloading a dependency-complete official package repository."
  pacman --config "$online_config" --dbpath "$db_path" --cachedir "$OFFICIAL_STAGE" \
    --sync --refresh --downloadonly --noconfirm "${packages[@]}"
  rm -f "$OFFICIAL_STAGE"/*.part

  mapfile -t package_files < <(find "$OFFICIAL_STAGE" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' -print | LC_ALL=C sort)
  ((${#package_files[@]} > 0)) || usb_die "No official package files were downloaded."

  db_temp=$(mktemp -d)
  repo-add -q "$db_temp/workstation.db.tar.gz" "${package_files[@]}"
  cp "$db_temp/workstation.db.tar.gz" "$OFFICIAL_STAGE/workstation.db"
  rm -rf "$db_temp" "$db_path" "$online_config"
  printf '%s\n' "${packages[@]}" > "$OFFICIAL_STAGE/packages.requested.txt"
  write_manifest "$OFFICIAL_STAGE"
  usb_ok "Official package cache staged."
}

if usb_bool_true "$WITH_AUR" && bool_true "$ENABLE_AUR"; then
  build_aur_stage
fi
build_official_stage
validate_staged_cache_pair
sync
activate_cache_pair
trap - EXIT
printf '%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$LAYOUT/state/last-package-refresh"
sync
usb_ok "The USB contains a complete checksum-verified offline repository for this workstation profile."
