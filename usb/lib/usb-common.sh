#!/usr/bin/env bash

USB_LAYOUT_NAME="MASON-ARCH"
USB_LAYOUT_VERSION="2"

usb_log() {
  local level=$1
  shift
  printf '[%s] %-7s %s\n' "$(date +'%H:%M:%S')" "$level" "$*"
}
usb_info() { usb_log INFO "$@"; }
usb_warn() { usb_log WARN "$@" >&2; }
usb_ok() { usb_log OK "$@"; }
usb_die() { usb_log ERROR "$@" >&2; exit 1; }

usb_bool_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

usb_github_repository_slug() {
  local url=${1%/} slug
  url=${url%.git}
  [[ $url == https://github.com/* ]] || return 1
  slug=${url#https://github.com/}
  [[ $slug =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]] || return 1
  printf '%s\n' "$slug"
}

usb_urlencode() {
  local LC_ALL=C input=$1 output="" character encoded index
  for ((index = 0; index < ${#input}; index++)); do
    character=${input:index:1}
    case "$character" in
      [A-Za-z0-9.~_-]) output+=$character ;;
      *)
        printf -v encoded '%%%02X' "'$character"
        output+=$encoded
        ;;
    esac
  done
  printf '%s\n' "$output"
}

usb_require_commands() {
  local missing=() command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done
  ((${#missing[@]} == 0)) || usb_die "Missing required commands: ${missing[*]}"
}

usb_set_config_defaults() {
  REPO_URL=""
  REPO_REF="main"
  REPO_PINNED_COMMIT=""
  INSTALL_CONFIG_SOURCE="repository"
  INSTALL_CONFIG_REPO_PATH="profiles/t480.conf"
  REPO_UPDATE_POLICY="always"
  ARCH_UPDATE_POLICY="always"
  PACKAGE_CACHE_UPDATE_POLICY="prompt"
  AUR_CACHE_UPDATE_POLICY="prompt"
  ARCH_MIRROR="https://geo.mirror.pkgbuild.com"
  NETWORK_CHECK_URL="https://archlinux.org/"
  KEEP_DOWNLOADED_ISO=false
  PACKAGE_CACHE_MIN_FREE_MIB=8192
  OFFER_WIFI_SETUP=true
}

usb_load_config() {
  local path=$1 policy bool_name
  usb_set_config_defaults
  # shellcheck source=/dev/null
  [[ -r $path ]] && source "$path"

  for policy in REPO_UPDATE_POLICY ARCH_UPDATE_POLICY PACKAGE_CACHE_UPDATE_POLICY AUR_CACHE_UPDATE_POLICY; do
    case "${!policy}" in
      always|prompt|never) ;;
      *) usb_die "$policy must be always, prompt, or never." ;;
    esac
  done
  case "$INSTALL_CONFIG_SOURCE" in
    repository|local) ;;
    *) usb_die "INSTALL_CONFIG_SOURCE must be repository or local." ;;
  esac
  [[ -n $INSTALL_CONFIG_REPO_PATH ]] \
    || usb_die "INSTALL_CONFIG_REPO_PATH must not be empty."
  [[ $INSTALL_CONFIG_REPO_PATH != *[[:space:]]* ]] \
    || usb_die "INSTALL_CONFIG_REPO_PATH must not contain whitespace."
  [[ $INSTALL_CONFIG_REPO_PATH != /* && $INSTALL_CONFIG_REPO_PATH != *'..'* ]] \
    || usb_die "INSTALL_CONFIG_REPO_PATH must be a safe path relative to the repository root."
  for bool_name in KEEP_DOWNLOADED_ISO OFFER_WIFI_SETUP; do
    case "${!bool_name,,}" in
      1|0|true|false|yes|no|on|off) ;;
      *) usb_die "$bool_name must be a boolean." ;;
    esac
  done
  if [[ -n $REPO_URL ]]; then
    usb_github_repository_slug "$REPO_URL" >/dev/null \
      || usb_die "REPO_URL must be a plain public HTTPS GitHub repository URL such as https://github.com/owner/repository."
  fi
  [[ $REPO_REF =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && $REPO_REF != *'..'* ]] \
    || usb_die "REPO_REF contains unsupported characters."
  if [[ -n $REPO_PINNED_COMMIT ]]; then
    [[ $REPO_PINNED_COMMIT =~ ^[0-9a-fA-F]{40}$ ]] \
      || usb_die "REPO_PINNED_COMMIT must be a full 40-character commit hash."
  fi
  [[ $ARCH_MIRROR == https://* ]] || usb_die "ARCH_MIRROR must use HTTPS."
  [[ $NETWORK_CHECK_URL == http://* || $NETWORK_CHECK_URL == https://* ]] \
    || usb_die "NETWORK_CHECK_URL must be an HTTP(S) URL."
  [[ $PACKAGE_CACHE_MIN_FREE_MIB =~ ^[0-9]+$ ]] \
    || usb_die "PACKAGE_CACHE_MIN_FREE_MIB must be an integer."
}

usb_ask_yes_no() {
  local prompt=$1 default=${2:-no} reply suffix
  if [[ $default == yes ]]; then suffix='[Y/n]'; else suffix='[y/N]'; fi
  read -r -p "$prompt $suffix " reply
  if [[ -z $reply ]]; then
    [[ $default == yes ]]
    return
  fi
  [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

usb_policy_allows() {
  local policy=$1 prompt=$2
  case "$policy" in
    always) return 0 ;;
    never) return 1 ;;
    prompt) usb_ask_yes_no "$prompt" no ;;
  esac
}

usb_network_available() {
  curl --connect-timeout 5 --max-time 15 --retry 1 -fsS "$NETWORK_CHECK_URL" -o /dev/null 2>/dev/null
}

usb_layout_dir() {
  local root=$1
  printf '%s/%s\n' "${root%/}" "$USB_LAYOUT_NAME"
}

usb_verify_layout() {
  local root=$1 layout
  layout=$(usb_layout_dir "$root")
  [[ -r $layout/.layout-version ]] || return 1
  [[ $(<"$layout/.layout-version") == "$USB_LAYOUT_VERSION" ]] || return 1
  [[ -r $layout/config/usb.conf ]] || return 1
  [[ -r $layout/config/install.conf ]] || return 1
}

usb_find_root() {
  local candidate source target
  for candidate in \
    "${MASON_USB_ROOT:-}" \
    /run/archiso/bootmnt \
    /run/mason-arch-usb \
    /mnt/mason-arch-usb; do
    [[ -n $candidate ]] || continue
    if usb_verify_layout "$candidate"; then
      readlink -f "$candidate"
      return 0
    fi
  done

  source=$(blkid -L MASON_ARCH 2>/dev/null || true)
  if [[ -n $source ]]; then
    target=$(findmnt -rn -S "$source" -o TARGET | head -n 1 || true)
    if [[ -n $target ]] && usb_verify_layout "$target"; then
      readlink -f "$target"
      return 0
    fi
  fi
  return 1
}

usb_try_remount_rw() {
  local root=$1 mount_target options probe
  mount_target=$(findmnt -rn -T "$root" -o TARGET | head -n 1 || true)
  [[ -n $mount_target ]] || return 1
  options=$(findmnt -rn -T "$root" -o OPTIONS | head -n 1)
  if [[ ,$options, == *,ro,* ]]; then
    mount -o remount,rw "$mount_target" || return 1
  fi
  probe="$root/.mason-write-test.$$"
  if ! (umask 077; : > "$probe") 2>/dev/null; then
    return 1
  fi
  rm -f "$probe" || return 1
}

usb_remount_rw() {
  local root=$1
  usb_try_remount_rw "$root" \
    || usb_die "The installer USB could not be made writable: $root"
}

usb_current_arch_slot() {
  local parameter
  for parameter in $(</proc/cmdline); do
    case "$parameter" in
      archisobasedir=arch-a) printf 'a\n'; return 0 ;;
      archisobasedir=arch-b) printf 'b\n'; return 0 ;;
    esac
  done
  return 1
}

usb_other_slot() {
  if [[ $1 == a ]]; then
    printf 'b\n'
  else
    printf 'a\n'
  fi
}

usb_verify_arch_slot() {
  local root=$1 slot=$2
  local base="$root/arch-$slot"
  [[ -s $base/version ]] || return 1
  [[ -s $base/boot/x86_64/vmlinuz-linux ]] || return 1
  [[ -s $base/boot/x86_64/initramfs-linux.img ]] || return 1
  [[ -s $base/x86_64/airootfs.sfs ]] || return 1
  [[ -s $base/x86_64/airootfs.sfs.cms.sig ]] || return 1
}

usb_read_active_slot() {
  local root=$1 layout slot
  layout=$(usb_layout_dir "$root")
  slot=$(sed -n 's/.*mason_active_slot="\([ab]\)".*/\1/p' "$layout/state/active-slot.cfg" 2>/dev/null | head -n 1)
  [[ $slot == a || $slot == b ]] || slot=a
  printf '%s\n' "$slot"
}

usb_write_active_slot() {
  local root=$1 slot=$2 layout temp
  [[ $slot == a || $slot == b ]] || usb_die "Invalid Arch slot: $slot"
  layout=$(usb_layout_dir "$root")
  temp="$layout/state/active-slot.cfg.new"
  mkdir -p "$layout/state"
  printf 'set mason_active_slot="%s"\n' "$slot" > "$temp"
  mv -f "$temp" "$layout/state/active-slot.cfg"
  sync "$layout/state/active-slot.cfg" 2>/dev/null || sync
}

usb_verify_sha_file() {
  local file=$1 hash_file=$2 expected actual
  [[ -s $file && -s $hash_file ]] || return 1
  expected=$(awk 'NR == 1 {print $1}' "$hash_file")
  actual=$(sha256sum "$file" | awk '{print $1}')
  [[ -n $expected && $actual == "$expected" ]]
}

usb_repository_required_paths() {
  cat <<'EOF_PATHS'
archctl
install.sh
config/install.conf.example
scripts/lib/common.sh
scripts/lib/config.sh
scripts/lib/install-source.sh
scripts/lib/packages.sh
scripts/install/01-preflight.sh
scripts/install/10-disk.sh
scripts/install/20-base.sh
scripts/install/chroot-configure.sh
usb/live-installer.sh
usb/refresh-arch.sh
usb/refresh-packages.sh
usb/verify-usb.sh
usb/lib/usb-common.sh
EOF_PATHS
}

usb_verify_repository_archive() {
  local archive=$1 hash_file=$2 listing required
  usb_verify_sha_file "$archive" "$hash_file" || return 1
  listing=$(tar -tzf "$archive") || return 1
  listing=$(printf '%s\n' "$listing" | sed 's#^\./##')
  while IFS= read -r required; do
    grep -Fqx -- "$required" <<< "$listing" || return 1
  done < <(usb_repository_required_paths)
}

usb_verify_directory_manifest() {
  local directory=$1
  [[ -s $directory/SHA256SUMS ]] || return 1
  (cd "$directory" && sha256sum --check --quiet SHA256SUMS)
}


usb_recover_interrupted_updates() {
  local root=$1 layout slot active other
  local official="$root/$USB_LAYOUT_NAME/cache/pacman"
  local aur="$root/$USB_LAYOUT_NAME/cache/aur"
  layout=$(usb_layout_dir "$root")

  # Recover a non-running Arch slot if power was lost between its rename steps.
  for slot in a b; do
    if usb_verify_arch_slot "$root" "$slot"; then
      rm -rf "$root/arch-$slot.old" "$root/arch-$slot.new"
    elif usb_verify_arch_slot "$root" "$slot.old"; then
      usb_warn "Restoring Arch slot $slot after an interrupted refresh."
      rm -rf "$root/arch-$slot"
      mv "$root/arch-$slot.old" "$root/arch-$slot"
      rm -rf "$root/arch-$slot.new"
    elif usb_verify_arch_slot "$root" "$slot.new"; then
      usb_warn "Completing staged Arch slot $slot after an interrupted refresh."
      rm -rf "$root/arch-$slot"
      mv "$root/arch-$slot.new" "$root/arch-$slot"
    fi
  done

  active=$(usb_read_active_slot "$root")
  if ! usb_verify_arch_slot "$root" "$active"; then
    other=$(usb_other_slot "$active")
    if usb_verify_arch_slot "$root" "$other"; then
      usb_warn "Selected Arch slot $active is invalid; switching to slot $other."
      usb_write_active_slot "$root" "$other"
    fi
  fi

  # Package caches are activated as a pair. If activation was interrupted and
  # the new pair is incomplete, restore the complete previous pair.
  if [[ -e ${official}.old || -e ${aur}.old ]]; then
    if usb_verify_directory_manifest "$official" \
      && { [[ ! -e ${aur}.old ]] || usb_verify_directory_manifest "$aur"; }; then
      rm -rf "${official}.old" "${aur}.old"
    elif usb_verify_directory_manifest "${official}.old" \
      && { [[ ! -e ${aur}.old ]] || usb_verify_directory_manifest "${aur}.old"; }; then
      usb_warn "Restoring the previous package-cache generation after an interrupted activation."
      rm -rf "$official" "$aur"
      mv "${official}.old" "$official"
      [[ ! -e ${aur}.old ]] || mv "${aur}.old" "$aur"
    fi
  fi
  rm -rf "${official}.new" "${aur}.new"

  mkdir -p "$layout/state"
}
