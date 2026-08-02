#!/usr/bin/env bash

INSTALL_SOURCE_RESOLVED="${INSTALL_SOURCE_RESOLVED:-}"
ONLINE_AVAILABLE="${ONLINE_AVAILABLE:-false}"
OFFLINE_PACMAN_CONFIG="${OFFLINE_PACMAN_CONFIG:-/run/arch-workstation/offline-pacman.conf}"

network_available() {
  local url=${NETWORK_CHECK_URL:-https://archlinux.org/}
  curl --connect-timeout 5 --max-time 15 --retry 1 -fsS "$url" -o /dev/null 2>/dev/null
}

verify_cache_manifest() {
  local directory=$1
  [[ -d $directory && -s $directory/SHA256SUMS ]] || return 1
  (cd "$directory" && sha256sum --check --quiet SHA256SUMS)
}

write_offline_pacman_config() {
  local output=$1
  local package_repo=$OFFLINE_REPO_PATH
  local aur_repo=${OFFLINE_AUR_REPO_PATH:-}

  [[ -d $package_repo && -s $package_repo/workstation.db ]] \
    || die "Offline package repository is incomplete: $package_repo"
  [[ $package_repo != *[[:space:]]* ]] \
    || die "Offline package repository paths must not contain whitespace: $package_repo"

  mkdir -p "$(dirname -- "$output")"
  cat > "$output" <<EOF_CONFIG
[options]
Architecture = auto
CheckSpace
ParallelDownloads = 5
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional

EOF_CONFIG

  if [[ -n $aur_repo ]]; then
    [[ -d $aur_repo && -s $aur_repo/workstation-aur.db ]] \
      || die "Offline AUR repository is incomplete: $aur_repo"
    [[ $aur_repo != *[[:space:]]* ]] \
      || die "Offline AUR repository paths must not contain whitespace: $aur_repo"
    cat >> "$output" <<EOF_CONFIG
[workstation-aur]
SigLevel = Optional TrustAll
Server = file://$aur_repo

EOF_CONFIG
  fi

  cat >> "$output" <<EOF_CONFIG
[workstation]
SigLevel = Optional TrustAll
Server = file://$package_repo
EOF_CONFIG
}

validate_offline_source() {
  local -a requested
  local db_path

  verify_cache_manifest "$OFFLINE_REPO_PATH" \
    || die "Offline package cache failed checksum verification: $OFFLINE_REPO_PATH"

  if bool_true "$ENABLE_AUR"; then
    [[ -n ${OFFLINE_AUR_REPO_PATH:-} ]] \
      || die "ENABLE_AUR=true but OFFLINE_AUR_REPO_PATH is not configured. Refresh the full USB cache first."
    verify_cache_manifest "$OFFLINE_AUR_REPO_PATH" \
      || die "Offline AUR cache failed checksum verification: $OFFLINE_AUR_REPO_PATH"
  fi

  write_offline_pacman_config "$OFFLINE_PACMAN_CONFIG"
  collect_all_requested_packages requested

  db_path=$(mktemp -d)
  mkdir -p "$db_path/local"
  if ! pacman --config "$OFFLINE_PACMAN_CONFIG" --dbpath "$db_path" --sync --refresh --noconfirm >/dev/null; then
    rm -rf "$db_path"
    die "The offline repository database could not be loaded."
  fi
  if ! pacman --config "$OFFLINE_PACMAN_CONFIG" --dbpath "$db_path" \
      --sync --print --print-format '%n' "${requested[@]}" >/dev/null; then
    rm -rf "$db_path"
    die "The offline cache does not resolve every requested package. Refresh the USB package cache before installing offline."
  fi
  rm -rf "$db_path"
}

resolve_install_source() {
  case "$INSTALL_SOURCE_MODE" in
    auto|online|offline) ;;
    *) die "INSTALL_SOURCE_MODE must be auto, online, or offline." ;;
  esac

  if network_available; then
    ONLINE_AVAILABLE=true
  else
    ONLINE_AVAILABLE=false
  fi

  case "$INSTALL_SOURCE_MODE" in
    online)
      bool_true "$ONLINE_AVAILABLE" || die "INSTALL_SOURCE_MODE=online but Arch mirrors are unreachable."
      INSTALL_SOURCE_RESOLVED=online
      ;;
    offline)
      validate_offline_source
      INSTALL_SOURCE_RESOLVED=offline
      ;;
    auto)
      if bool_true "$ONLINE_AVAILABLE"; then
        INSTALL_SOURCE_RESOLVED=online
      else
        validate_offline_source
        INSTALL_SOURCE_RESOLVED=offline
      fi
      ;;
  esac
}
