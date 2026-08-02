#!/usr/bin/env bash
set -Eeuo pipefail

# Archiso copies an automated script to /tmp before executing it. This stable
# loader selects a verified repository generation and hands over to that code.

find_common_library() {
  local candidate
  for candidate in \
    /run/archiso/bootmnt/MASON-ARCH/runtime/usb-common.sh \
    /run/mason-arch-usb/MASON-ARCH/runtime/usb-common.sh \
    /mnt/mason-arch-usb/MASON-ARCH/runtime/usb-common.sh; do
    [[ -r $candidate ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

COMMON_LIBRARY=$(find_common_library) || {
  echo 'Mason installer USB runtime library was not found.' >&2
  exit 1
}
# shellcheck source=lib/usb-common.sh
source "$COMMON_LIBRARY"

[[ ${EUID:-$(id -u)} -eq 0 ]] || usb_die "The live loader must run as root."
USB_ROOT=$(usb_find_root) || usb_die "The MASON_ARCH USB filesystem could not be located."
LAYOUT=$(usb_layout_dir "$USB_ROOT")
USB_CONFIG="$LAYOUT/config/usb.conf"
INSTALL_CONFIG="$LAYOUT/config/install.conf"
REPOSITORY_CACHE="$LAYOUT/cache/repository"
RUN_ROOT=/run/mason-installer

usb_load_config "$USB_CONFIG"
usb_require_commands awk curl find grep sed sha256sum tar
USB_WRITABLE=false
if usb_try_remount_rw "$USB_ROOT"; then
  USB_WRITABLE=true
  mkdir -p "$REPOSITORY_CACHE"
  usb_recover_interrupted_updates "$USB_ROOT"
else
  usb_warn "The USB is read-only. Cached boot, configuration and packages remain usable, but refresh operations are disabled."
fi
mkdir -p "$RUN_ROOT"

# The automated script can start while live services are still settling.
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-system-running --wait >/dev/null 2>&1 || true
fi

NETWORK_AVAILABLE=false
if usb_network_available; then
  NETWORK_AVAILABLE=true
else
  usb_warn "No working internet connection was detected."
  if usb_bool_true "$OFFER_WIFI_SETUP" && command -v iwctl >/dev/null 2>&1; then
    if usb_ask_yes_no "Open iwctl to connect Wi-Fi?" yes; then
      iwctl
      if usb_network_available; then NETWORK_AVAILABLE=true; fi
    fi
  fi
fi

verify_repository_snapshot() {
  local name=$1
  usb_verify_repository_archive \
    "$REPOSITORY_CACHE/$name.tar.gz" \
    "$REPOSITORY_CACHE/$name.sha256"
}

rotate_repository_snapshot() {
  local archive=$1 commit=$2 new_hash
  local previous_archive="$REPOSITORY_CACHE/previous.tar.gz.new"
  local previous_hash="$REPOSITORY_CACHE/previous.sha256.new"
  local current_hash="$REPOSITORY_CACHE/current.sha256.new"
  new_hash=$(sha256sum "$archive" | awk '{print $1}') || return 1

  # Copy rather than move the current generation. Until the previous copy has
  # been verified and synced, current remains untouched and bootable.
  if verify_repository_snapshot current; then
    cp -f "$REPOSITORY_CACHE/current.tar.gz" "$previous_archive" || return 1
    printf '%s  previous.tar.gz\n' \
      "$(sha256sum "$previous_archive" | awk '{print $1}')" > "$previous_hash" || return 1
    usb_verify_sha_file "$previous_archive" "$previous_hash" || return 1
    mv -f "$previous_archive" "$REPOSITORY_CACHE/previous.tar.gz" || return 1
    mv -f "$previous_hash" "$REPOSITORY_CACHE/previous.sha256" || return 1
    [[ ! -e $REPOSITORY_CACHE/current.commit ]] \
      || cp -f "$REPOSITORY_CACHE/current.commit" "$REPOSITORY_CACHE/previous.commit" \
      || return 1
    sync "$REPOSITORY_CACHE/previous.tar.gz" 2>/dev/null || sync
    verify_repository_snapshot previous || return 1
  fi

  printf '%s  current.tar.gz\n' "$new_hash" > "$current_hash" || return 1
  usb_verify_sha_file "$archive" "$current_hash" || return 1
  mv -f "$archive" "$REPOSITORY_CACHE/current.tar.gz" || return 1
  mv -f "$current_hash" "$REPOSITORY_CACHE/current.sha256" || return 1
  printf '%s\n' "$commit" > "$REPOSITORY_CACHE/current.commit" || return 1
  sync "$REPOSITORY_CACHE/current.tar.gz" 2>/dev/null || sync
  verify_repository_snapshot current || return 1
}

update_repository_snapshot() {
  local temp_root source_archive source_metadata clone_dir archive commit required script
  local repository_slug encoded_ref api_url
  [[ -n $REPO_URL ]] || return 1
  repository_slug=$(usb_github_repository_slug "$REPO_URL") || return 1
  temp_root=$(mktemp -d)
  source_archive="$temp_root/source.tar.gz"
  source_metadata="$temp_root/commit.json"
  clone_dir="$temp_root/repository"
  mkdir -p "$clone_dir"
  archive="$REPOSITORY_CACHE/current.tar.gz.new"
  rm -f "$archive"

  usb_info "Downloading repository configuration from $REPO_URL ($REPO_REF)."
  if [[ -n $REPO_PINNED_COMMIT ]]; then
    commit=${REPO_PINNED_COMMIT,,}
  else
    encoded_ref=$(usb_urlencode "$REPO_REF")
    api_url="https://api.github.com/repos/$repository_slug/commits/$encoded_ref"
    if ! curl -fL --retry 3 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "$api_url" -o "$source_metadata"; then
      rm -rf "$temp_root"
      return 1
    fi
    commit=$(sed -nE 's/^[[:space:]]*"sha":[[:space:]]*"([0-9a-fA-F]{40})",?$/\1/p' "$source_metadata" | head -n 1)
  fi

  if [[ ! $commit =~ ^[0-9a-fA-F]{40}$ ]]; then
    rm -rf "$temp_root"
    usb_warn "GitHub did not return a full commit hash for $REPO_REF."
    return 1
  fi
  commit=${commit,,}

  if ! curl -fL --retry 3 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repository_slug/tarball/$commit" \
    -o "$source_archive"; then
    rm -rf "$temp_root"
    return 1
  fi
  if ! tar -xzf "$source_archive" --strip-components=1 -C "$clone_dir"; then
    rm -rf "$temp_root"
    return 1
  fi

  while IFS= read -r required; do
    [[ -f $clone_dir/$required && ! -L $clone_dir/$required ]] || {
      rm -rf "$temp_root"
      usb_warn "Downloaded repository is missing $required."
      return 1
    }
  done < <(usb_repository_required_paths)
  if [[ $INSTALL_CONFIG_SOURCE == repository ]] \
    && { [[ ! -f $clone_dir/$INSTALL_CONFIG_REPO_PATH ]] \
      || [[ -L $clone_dir/$INSTALL_CONFIG_REPO_PATH ]]; }; then
    rm -rf "$temp_root"
    usb_warn "Downloaded repository is missing configured profile: $INSTALL_CONFIG_REPO_PATH"
    return 1
  fi
  while IFS= read -r -d '' script; do
    bash -n "$script" || { rm -rf "$temp_root"; return 1; }
  done < <(find "$clone_dir" -type f -name '*.sh' -print0)

  if ! (
    cd "$clone_dir"
    tar -czf "$archive" .
  ); then
    rm -rf "$temp_root" "$archive"
    return 1
  fi
  rm -rf "$temp_root"
  rotate_repository_snapshot "$archive" "$commit" || return 1
  usb_ok "Repository cache updated to commit $commit."
}

if [[ -n $REPO_URL && $NETWORK_AVAILABLE == true && $USB_WRITABLE == true ]]; then
  if usb_policy_allows "$REPO_UPDATE_POLICY" "Download the latest installer configuration from GitHub?"; then
    if ! update_repository_snapshot; then
      usb_warn "Repository update failed; the verified USB snapshot will be used."
    fi
  fi
fi

SNAPSHOT_NAME=""
if verify_repository_snapshot current; then
  SNAPSHOT_NAME=current
elif verify_repository_snapshot previous; then
  SNAPSHOT_NAME=previous
  usb_warn "The current repository snapshot is invalid; using the previous verified copy."
else
  usb_die "Neither repository snapshot passed checksum verification. Rebuild the installer USB."
fi

SNAPSHOT_COMMIT=source-archive
if [[ -r $REPOSITORY_CACHE/$SNAPSHOT_NAME.commit ]]; then
  cached_commit=""
  read -r cached_commit < "$REPOSITORY_CACHE/$SNAPSHOT_NAME.commit" || true
  if [[ $cached_commit =~ ^[0-9a-fA-F]{40}(-dirty)?$ || $cached_commit == source-tree ]]; then
    SNAPSHOT_COMMIT=${cached_commit,,}
  fi
fi

rm -rf "$RUN_ROOT/repo"
mkdir -p "$RUN_ROOT/repo"
tar -xzf "$REPOSITORY_CACHE/$SNAPSHOT_NAME.tar.gz" -C "$RUN_ROOT/repo"

SELECTED_INSTALL_CONFIG="$INSTALL_CONFIG"
INSTALL_CONFIG_DESCRIPTION="local USB fallback"
if [[ $INSTALL_CONFIG_SOURCE == repository ]]; then
  repository_profile="$RUN_ROOT/repo/$INSTALL_CONFIG_REPO_PATH"
  if [[ -r $repository_profile ]]; then
    SELECTED_INSTALL_CONFIG="$repository_profile"
    INSTALL_CONFIG_DESCRIPTION="repository:$INSTALL_CONFIG_REPO_PATH"
  else
    usb_warn "Snapshot $SNAPSHOT_NAME has no $INSTALL_CONFIG_REPO_PATH; using the local USB profile."
  fi
fi
install -Dm0600 "$SELECTED_INSTALL_CONFIG" "$RUN_ROOT/repo/config/install.conf"

export MASON_USB_ROOT="$USB_ROOT"
export MASON_REPO_SOURCE="$SNAPSHOT_NAME"
export MASON_REPO_COMMIT="$SNAPSHOT_COMMIT"
export MASON_INSTALL_CONFIG_SOURCE="$INSTALL_CONFIG_DESCRIPTION"
export MASON_NETWORK_AVAILABLE="$NETWORK_AVAILABLE"
export MASON_USB_WRITABLE="$USB_WRITABLE"
exec bash "$RUN_ROOT/repo/usb/live-installer.sh" \
  --usb-root "$USB_ROOT" \
  --repo-root "$RUN_ROOT/repo" \
  --install-config "$RUN_ROOT/repo/config/install.conf"
