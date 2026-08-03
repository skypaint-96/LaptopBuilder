#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT=""
CONFIG_FILE="$REPO_ROOT/config/install.conf"
SOURCE_REPO="$REPO_ROOT"
REPO_URL=""
REPO_REF="main"
REFRESH_REPO=true
REFRESH_ARCHISO=true
REFRESH_PACKAGES=true
ARCHISO_LATEST_BASE="${ARCHISO_LATEST_BASE:-https://geo.mirror.pkgbuild.com/iso/latest}"
REQUIRED_USB_API_VERSION=$(cat "$REPO_ROOT/usb/API_VERSION")

# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/usb/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: sudo ./usb/cache.sh --cache-root PATH [options]

Refreshes the persistent project, official Arch ISO, and official package caches.
It does not perform an installation.

Options:
  --cache-root PATH      Persistent cache root (required)
  --config PATH          Installation configuration used for package selection
  --source-repo PATH     Local committed repository used as a seed
  --repo-url URL         Live Git repository URL
  --repo-ref REF         Branch, tag, or commit selected at boot (default: main)
  --repo-only            Refresh only the project repository cache
  --archiso-only         Refresh only the official Arch ISO backup
  --packages-only        Refresh only official package databases/packages
  --skip-repo            Do not refresh the project cache
  --skip-archiso         Do not refresh the official ISO backup
  --skip-packages        Do not refresh official package caches
USAGE
}

while (($#)); do
  case "$1" in
    --cache-root)
      [[ $# -ge 2 ]] || die '--cache-root requires a path.'
      CACHE_ROOT=$2
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die '--config requires a path.'
      CONFIG_FILE=$2
      shift 2
      ;;
    --source-repo)
      [[ $# -ge 2 ]] || die '--source-repo requires a path.'
      SOURCE_REPO=$2
      shift 2
      ;;
    --repo-url)
      [[ $# -ge 2 ]] || die '--repo-url requires a URL.'
      REPO_URL=$2
      shift 2
      ;;
    --repo-ref)
      [[ $# -ge 2 ]] || die '--repo-ref requires a value.'
      REPO_REF=$2
      shift 2
      ;;
    --repo-only)
      REFRESH_REPO=true; REFRESH_ARCHISO=false; REFRESH_PACKAGES=false
      shift
      ;;
    --archiso-only)
      REFRESH_REPO=false; REFRESH_ARCHISO=true; REFRESH_PACKAGES=false
      shift
      ;;
    --packages-only)
      REFRESH_REPO=false; REFRESH_ARCHISO=false; REFRESH_PACKAGES=true
      shift
      ;;
    --skip-repo)
      REFRESH_REPO=false
      shift
      ;;
    --skip-archiso)
      REFRESH_ARCHISO=false
      shift
      ;;
    --skip-packages)
      REFRESH_PACKAGES=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown cache option: $1"
      ;;
  esac
done

require_root
[[ -n $CACHE_ROOT ]] || die '--cache-root is required.'
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
[[ -d $SOURCE_REPO ]] || die "Source repository directory not found: $SOURCE_REPO"
mkdir -p "$CACHE_ROOT"
CACHE_ROOT=$(readlink -f "$CACHE_ROOT")
SOURCE_REPO=$(readlink -f "$SOURCE_REPO")
REPO_URL=$(normalise_public_git_url "$REPO_URL")
validate_git_repository_source "$REPO_URL" "$REPO_REF"
load_config "$CONFIG_FILE"
validate_config runtime

checkout_cache_ref() {
  local repo=$1 ref=$2
  git -C "$repo" checkout --detach "$ref" >/dev/null 2>&1 \
    || git -C "$repo" checkout "$ref" >/dev/null 2>&1 \
    || git -C "$repo" checkout --detach "origin/$ref" >/dev/null 2>&1
}

seed_mirror_from_local() {
  local source=$1 destination=$2 snapshot path
  snapshot=$(mktemp -d "$(dirname -- "$destination")/source-snapshot.XXXXXX")
  copy_tracked_repository "$source" "$snapshot"
  prepare_project_tree "$snapshot" "$REQUIRED_USB_API_VERSION" \
    || die "Project snapshot from $source is incompatible with USB API $REQUIRED_USB_API_VERSION."

  git -C "$snapshot" init -q -b cache-snapshot
  git -C "$snapshot" config user.name 'arch-workstation cache'
  git -C "$snapshot" config user.email 'cache@localhost.invalid'
  git -C "$snapshot" add -A
  for path in \
    start.sh install.sh archctl build-usb.sh upgrade-existing.sh \
    usb/cache.sh usb/configure.sh usb/secrets.sh usb/build.sh \
    usb/live/archws-live usb/lib/common.sh; do
    [[ -f $snapshot/$path ]] || continue
    git -C "$snapshot" update-index --chmod=+x -- "$path"
  done
  while IFS= read -r -d '' path; do
    path=${path#"$snapshot/"}
    git -C "$snapshot" update-index --chmod=+x -- "$path"
  done < <(find -P "$snapshot/usb" "$snapshot/scripts" -type f -name '*.sh' -print0 2>/dev/null)
  git -C "$snapshot" commit -qm 'Normalised USB project cache snapshot'
  git -C "$snapshot" clone --mirror -- "$snapshot" "$destination"
  rm -rf "$snapshot"
}

refresh_repository_cache() {
  require_commands git
  local destination="$CACHE_ROOT/repo" temp_parent temp_mirror commit cached_api
  local source_checkout='' source_for_cache="$SOURCE_REPO" source_description='local source'
  mkdir -p "$destination"
  temp_parent=$(mktemp -d "$destination/.refresh.XXXXXX")
  temp_mirror="$temp_parent/mirror.git"
  trap 'rm -rf "${temp_parent:-}"' EXIT

  info "Refreshing project repository cache for ref '$REPO_REF'."
  if [[ -n $REPO_URL ]]; then
    source_checkout="$temp_parent/live-source"
    if GIT_TERMINAL_PROMPT=0 git clone -- "$REPO_URL" "$source_checkout" \
      && checkout_cache_ref "$source_checkout" "$REPO_REF" \
      && prepare_project_tree "$source_checkout" "$REQUIRED_USB_API_VERSION"; then
      source_for_cache=$source_checkout
      source_description='live source'
    else
      warn "The live source could not provide a compatible USB API $REQUIRED_USB_API_VERSION project; caching the local builder snapshot instead."
      rm -rf "$source_checkout"
      source_checkout=''
      source_for_cache=$SOURCE_REPO
    fi
  fi

  seed_mirror_from_local "$source_for_cache" "$temp_mirror"
  commit=$(git --git-dir="$temp_mirror" rev-parse HEAD)
  cached_api=$(git --git-dir="$temp_mirror" show "$commit:usb/API_VERSION" 2>/dev/null | tr -d '[:space:]' || true)
  [[ $cached_api == "$REQUIRED_USB_API_VERSION" ]] \
    || die "The normalised project cache is incompatible with USB API $REQUIRED_USB_API_VERSION."

  git --git-dir="$temp_mirror" fsck --no-progress
  git --git-dir="$temp_mirror" bundle create "$temp_parent/project.bundle" --all
  git --git-dir="$temp_mirror" bundle verify "$temp_parent/project.bundle" >/dev/null

  cat > "$temp_parent/repository.env" <<EOF_REPO
ARCHWS_REPO_URL=$(usb_quote "$REPO_URL")
ARCHWS_REPO_REF=$(usb_quote "$REPO_REF")
ARCHWS_REPO_COMMIT=$(usb_quote "$commit")
ARCHWS_USB_API_VERSION=$(usb_quote "$cached_api")
ARCHWS_REPO_CACHE_SOURCE=$(usb_quote "$source_description")
ARCHWS_REPO_REFRESHED_AT=$(usb_quote "$(date --iso-8601=seconds)")
EOF_REPO

  rm -rf "$destination/mirror.git.previous"
  if [[ -d $destination/mirror.git ]]; then
    mv "$destination/mirror.git" "$destination/mirror.git.previous"
  fi
  mv "$temp_mirror" "$destination/mirror.git"
  install -m 0644 "$temp_parent/project.bundle" "$destination/project.bundle.new"
  mv -f "$destination/project.bundle.new" "$destination/project.bundle"
  install -m 0644 "$temp_parent/repository.env" "$destination/repository.env"
  rm -rf "$destination/mirror.git.previous"
  success "Project cache now contains normalised $source_description snapshot $commit"
  rm -rf "$temp_parent"
  trap - EXIT
}

refresh_archiso_cache() {
  require_commands awk curl gpg sha256sum
  local destination="$CACHE_ROOT/archiso" sums_temp iso_name expected actual iso_temp
  mkdir -p "$destination"
  sums_temp=$(mktemp "$destination/.sha256sums.XXXXXX")
  trap 'rm -f "${sums_temp:-}" "${iso_temp:-}"' EXIT

  info 'Checking the current official Arch installation ISO.'
  curl --fail --location --retry 3 --connect-timeout 15 \
    "$ARCHISO_LATEST_BASE/sha256sums.txt" -o "$sums_temp"
  iso_name=$(awk '$2 ~ /^archlinux-[0-9.]+-x86_64\.iso$/ {print $2; exit}' "$sums_temp")
  expected=$(awk -v name="$iso_name" '$2 == name {print $1; exit}' "$sums_temp")
  [[ -n $iso_name && -n $expected ]] || die 'Could not identify the current x86-64 ISO in sha256sums.txt.'

  if [[ -f $destination/$iso_name ]]; then
    actual=$(sha256sum "$destination/$iso_name" | awk '{print $1}')
  else
    actual=''
  fi

  if [[ $actual != "$expected" ]]; then
    iso_temp="$destination/.${iso_name}.partial"
    rm -f "$iso_temp"
    info "Downloading $iso_name into the offline cache."
    curl --fail --location --retry 5 --continue-at - \
      "$ARCHISO_LATEST_BASE/$iso_name" -o "$iso_temp"
    actual=$(sha256sum "$iso_temp" | awk '{print $1}')
    [[ $actual == "$expected" ]] || die "Checksum mismatch for downloaded $iso_name."
    mv -f "$iso_temp" "$destination/$iso_name"
  else
    info "$iso_name is already current and verified."
  fi

  install -m 0644 "$sums_temp" "$destination/sha256sums.txt"
  if curl --fail --location --retry 2 \
      "$ARCHISO_LATEST_BASE/${iso_name}.sig" -o "$destination/${iso_name}.sig.tmp"; then
    mv -f "$destination/${iso_name}.sig.tmp" "$destination/${iso_name}.sig"
    if [[ -d /etc/pacman.d/gnupg ]]; then
      if gpg --homedir /etc/pacman.d/gnupg --batch --verify \
          "$destination/${iso_name}.sig" "$destination/$iso_name" >/dev/null 2>&1; then
        success 'The official ISO checksum and detached signature both verify.'
      else
        warn 'The checksum verifies, but the detached signature could not be validated with the local pacman keyring.'
      fi
    fi
  else
    rm -f "$destination/${iso_name}.sig.tmp"
    warn 'The ISO checksum was verified, but its detached signature could not be downloaded.'
  fi

  find "$destination" -maxdepth 1 -type f -name 'archlinux-*-x86_64.iso' ! -name "$iso_name" -delete
  cat > "$destination/current.env" <<EOF_ISO
ARCHWS_ARCHISO_FILE=$(usb_quote "$iso_name")
ARCHWS_ARCHISO_SHA256=$(usb_quote "$expected")
ARCHWS_ARCHISO_REFRESHED_AT=$(usb_quote "$(date --iso-8601=seconds)")
EOF_ISO

  rm -f "$sums_temp"
  trap - EXIT
  success "Official Arch ISO backup is current: $iso_name"
}

write_cache_pacman_conf() {
  local path=$1
  cat > "$path" <<'EOF_PACMAN'
[options]
Architecture = auto
Color
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
EOF_PACMAN
}

refresh_package_cache() {
  require_commands pacman sort
  local destination="$CACHE_ROOT/pacman" db_path pkg_path conf_path log_path manifest
  destination=$(readlink -m "$destination")
  db_path="$destination/db"
  pkg_path="$destination/pkg"
  conf_path="$destination/pacman.conf"
  log_path="$destination/pacman.log"
  manifest="$destination/package-manifest.txt"
  mkdir -p "$db_path/local" "$db_path/sync" "$pkg_path"
  write_cache_pacman_conf "$conf_path"
  rm -f "$db_path/db.lck"

  # shellcheck source=../scripts/install/20-base.sh
  source "$REPO_ROOT/scripts/install/20-base.sh"
  build_package_lists
  REQUIRED_OFFICIAL_PACKAGES+=(archlinux-keyring)
  mapfile -t REQUIRED_OFFICIAL_PACKAGES < <(printf '%s\n' "${REQUIRED_OFFICIAL_PACKAGES[@]}" | sort -u)

  info "Refreshing official package databases and caching ${#REQUIRED_OFFICIAL_PACKAGES[@]} configured package roots plus dependencies."
  pacman --config "$conf_path" --dbpath "$db_path" --cachedir "$pkg_path" \
    --logfile "$log_path" -Syw --noconfirm "${REQUIRED_OFFICIAL_PACKAGES[@]}"

  pacman --config "$conf_path" --dbpath "$db_path" --cachedir "$pkg_path" \
    -Sp --print-format '%n %v %r' "${REQUIRED_OFFICIAL_PACKAGES[@]}" \
    | sort -u > "$manifest"
  cp -f /etc/pacman.d/mirrorlist "$destination/mirrorlist.last-used"
  cat > "$destination/cache.env" <<EOF_CACHE
ARCHWS_PACKAGE_CACHE_REFRESHED_AT=$(usb_quote "$(date --iso-8601=seconds)")
ARCHWS_PACKAGE_ROOT_COUNT=${#REQUIRED_OFFICIAL_PACKAGES[@]}
EOF_CACHE

  if command -v paccache >/dev/null 2>&1; then
    paccache -rk2 -c "$pkg_path" >/dev/null || warn 'Package cache pruning reported a non-fatal error.'
  fi
  success "Official package cache refreshed ($(du -sh "$pkg_path" | awk '{print $1}'))."
}

bool_true "$REFRESH_REPO" && refresh_repository_cache
bool_true "$REFRESH_ARCHISO" && refresh_archiso_cache
bool_true "$REFRESH_PACKAGES" && refresh_package_cache

sync
success "Cache refresh completed under $CACHE_ROOT"
