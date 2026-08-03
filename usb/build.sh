#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config/install.conf"
SECURE_FILE=""
DEVICE=""
REPO_URL=""
REPO_REF=""
OUTPUT_DIR="$REPO_ROOT/usb/output"
WORK_DIR="$REPO_ROOT/usb/work"
INCLUDE_SECRETS=auto
CONFIGURE_MODE=auto
CONFIG_ACTION_EXPLICIT=false
SECRETS_ACTION_EXPLICIT=false
REPO_URL_EXPLICIT=false
REPO_REF_EXPLICIT=false
REFRESH_CACHE=true
WRITE_USB=true
REFRESH_ONLY=false
ASSUME_YES=false
KEEP_WORK=false
WORK_PREPARED=false
declare -a CONFIG_SET_VALUES=()
CUSTOM_ISO=""
ENCRYPTED_BUNDLE=""
MEDIA_CONFIG=""
MOUNT_DIR=""
TEMP_ROOT=""
DATA_PART=""
VERSION=$(cat "$REPO_ROOT/VERSION" 2>/dev/null || printf development)
REQUIRED_USB_API_VERSION=$(tr -d '[:space:]' < "$REPO_ROOT/usb/API_VERSION")

# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/usb/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: ./build-usb.sh [options]

Build a custom ArchISO and optionally write it to a USB with a persistent
ARCHWS_DATA partition for configuration, encrypted secrets, project cache,
official Arch ISO backup, package databases, and package files.

Options:
  --device /dev/sdX       Whole USB device to erase and write
  --config PATH           Installation configuration
  --configure             Run guided configuration before building
  --edit-config           Open configuration in $EDITOR
  --no-configure          Use the supplied/current configuration as-is
  --set KEY=VALUE         Set an approved install option; may be repeated
  --secure-file PATH      0400/0600 JSON file containing any secret fields
  --include-secrets       Store an encrypted installation-secret bundle
  --no-secrets            Do not store installation credentials on the USB
  --repo-url URL          Live project Git URL (defaults to origin)
  --repo-ref REF          Live branch/tag/commit (defaults to current branch/main)
  --output-dir PATH       ISO output directory
  --iso-only              Build the ISO but do not write a USB
  --refresh-only          Refresh an existing ARCHWS_DATA cache without rebuilding
  --no-refresh-cache      Do not pre-populate/refresh persistent online caches
  --yes                   Accept the exact USB write confirmation non-interactively
  --keep-work             Keep generated ArchISO work/profile directories
  -h, --help              Show this help

Secure JSON fields:
  username, user_password, luks_passphrase, tpm2_pin,
  media_unlock_passphrase

Missing requested secret fields are prompted together before the lengthy build.
USAGE
}

cleanup() {
  local code=$?
  if [[ -n $MOUNT_DIR ]] && findmnt -rn "$MOUNT_DIR" >/dev/null 2>&1; then
    sudo umount "$MOUNT_DIR" || true
  fi
  if [[ -n $TEMP_ROOT && -d $TEMP_ROOT ]]; then
    rm -rf "$TEMP_ROOT"
  fi
  if bool_true "$WORK_PREPARED" && ! bool_true "$KEEP_WORK" && [[ -d $WORK_DIR ]]; then
    sudo rm -rf "$WORK_DIR" 2>/dev/null || true
  fi
  stop_sudo_keepalive
  unset ENCRYPTED_BUNDLE
  exit "$code"
}
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || die '--device requires a whole-disk path.'
      DEVICE=$2
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || die '--config requires a path.'
      CONFIG_FILE=$2
      CONFIG_ACTION_EXPLICIT=true
      shift 2
      ;;
    --configure)
      CONFIGURE_MODE=guided
      CONFIG_ACTION_EXPLICIT=true
      shift
      ;;
    --edit-config)
      CONFIGURE_MODE=editor
      CONFIG_ACTION_EXPLICIT=true
      shift
      ;;
    --no-configure)
      CONFIGURE_MODE=none
      CONFIG_ACTION_EXPLICIT=true
      shift
      ;;
    --set)
      [[ $# -ge 2 && $2 == *=* ]] || die '--set requires KEY=VALUE.'
      CONFIG_SET_VALUES+=("$2")
      CONFIG_ACTION_EXPLICIT=true
      shift 2
      ;;
    --secure-file)
      [[ $# -ge 2 ]] || die '--secure-file requires a path.'
      SECURE_FILE=$2
      if [[ $INCLUDE_SECRETS == auto ]]; then
        INCLUDE_SECRETS=true
      fi
      SECRETS_ACTION_EXPLICIT=true
      shift 2
      ;;
    --include-secrets)
      INCLUDE_SECRETS=true
      SECRETS_ACTION_EXPLICIT=true
      shift
      ;;
    --no-secrets)
      INCLUDE_SECRETS=false
      SECRETS_ACTION_EXPLICIT=true
      shift
      ;;
    --repo-url)
      [[ $# -ge 2 ]] || die '--repo-url requires a URL.'
      REPO_URL=$2
      REPO_URL_EXPLICIT=true
      shift 2
      ;;
    --repo-ref)
      [[ $# -ge 2 ]] || die '--repo-ref requires a value.'
      REPO_REF=$2
      REPO_REF_EXPLICIT=true
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die '--output-dir requires a path.'
      OUTPUT_DIR=$2
      shift 2
      ;;
    --iso-only)
      WRITE_USB=false
      shift
      ;;
    --refresh-only)
      REFRESH_ONLY=true
      WRITE_USB=false
      shift
      ;;
    --no-refresh-cache)
      REFRESH_CACHE=false
      shift
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    --keep-work)
      KEEP_WORK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown USB-builder option: $1"
      ;;
  esac
done

require_non_root
require_commands awk cp pacman readlink sed stat sudo
[[ -f /etc/arch-release ]] || die 'The USB builder must run on an Arch Linux system.'
if bool_true "$REFRESH_ONLY" && ! bool_true "$REFRESH_CACHE"; then
  die '--refresh-only and --no-refresh-cache cannot be combined.'
fi
if ! bool_true "$WRITE_USB" && ! bool_true "$REFRESH_ONLY"; then
  if bool_true "$SECRETS_ACTION_EXPLICIT" && bool_true "$INCLUDE_SECRETS"; then
    die '--iso-only cannot store installation secrets because the encrypted bundle belongs on the writable ARCHWS_DATA partition.'
  fi
  if [[ $INCLUDE_SECRETS == auto ]]; then
    INCLUDE_SECRETS=false
  fi
fi
start_sudo_keepalive

ensure_builder_packages() {
  local -a required_packages=(curl e2fsprogs git gnupg gptfdisk jq pacman-contrib rsync util-linux)
  if ! bool_true "$REFRESH_ONLY"; then
    required_packages+=(archiso)
  fi
  local -a missing=()
  local package
  for package in "${required_packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  if ((${#missing[@]})); then
    info "Installing USB-builder dependencies: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
  require_commands \
    awk base64 cmp cp curl dd e2fsck findmnt findfs git gpg jq lsblk mkfs.ext4 mount pacman \
    partprobe readlink rsync sed sfdisk sgdisk sha256sum stat swapon tar udevadm umount wipefs
  if ! bool_true "$REFRESH_ONLY"; then
    require_commands mkarchiso
  fi
}

ensure_configuration() {
  if [[ ! -e $CONFIG_FILE ]]; then
    mkdir -p "$(dirname -- "$CONFIG_FILE")"
    cp "$REPO_ROOT/config/install.conf.example" "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE"
    if [[ $CONFIGURE_MODE == auto ]] && ((${#CONFIG_SET_VALUES[@]} == 0)); then
      CONFIGURE_MODE=guided
    fi
  fi
  [[ -f $CONFIG_FILE && ! -L $CONFIG_FILE ]] || die "Configuration must be a regular file: $CONFIG_FILE"

  if ((${#CONFIG_SET_VALUES[@]})); then
    local -a set_args=()
    local assignment
    for assignment in "${CONFIG_SET_VALUES[@]}"; do
      set_args+=(--set "$assignment")
    done
    "$REPO_ROOT/usb/configure.sh" --config "$CONFIG_FILE" "${set_args[@]}"
    if [[ $CONFIGURE_MODE == auto ]]; then
      CONFIGURE_MODE=none
    fi
  fi

  if [[ $CONFIGURE_MODE == auto ]]; then
    cat <<EOF_CONFIG

Configuration source: $CONFIG_FILE
  1) Use it unchanged (default)
  2) Run guided configuration
  3) Open it in an editor
EOF_CONFIG
    read -r -p 'Select [1]: ' config_choice
    case "${config_choice:-1}" in
      1) CONFIGURE_MODE=none ;;
      2) CONFIGURE_MODE=guided ;;
      3) CONFIGURE_MODE=editor ;;
      *) die "Unknown configuration selection: $config_choice" ;;
    esac
  fi

  case "$CONFIGURE_MODE" in
    guided) "$REPO_ROOT/usb/configure.sh" --config "$CONFIG_FILE" --guided ;;
    editor) "$REPO_ROOT/usb/configure.sh" --config "$CONFIG_FILE" --editor ;;
    none) ;;
    *) die "Unknown configuration mode: $CONFIGURE_MODE" ;;
  esac

  load_config "$CONFIG_FILE"
  validate_config runtime
  chmod 0600 "$CONFIG_FILE"
}

detect_repository_source() {
  if [[ -z $REPO_URL ]]; then
    REPO_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
    case "$REPO_URL" in
      /*|file://*|*.bundle) REPO_URL='' ;;
    esac
  fi
  REPO_URL=$(normalise_public_git_url "$REPO_URL")
  if [[ -z $REPO_REF ]]; then
    REPO_REF=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    REPO_REF=${REPO_REF:-main}
  fi

  if [[ -z $REPO_URL ]]; then
    warn 'No network Git URL was detected. The USB will still use its cache/embedded copy, but live project refresh will be unavailable.'
    if [[ -t 0 ]]; then
      prompt_with_default REPO_URL 'Credential-free live Git URL, or leave blank' ''
    fi
  fi
  REPO_URL=$(normalise_public_git_url "$REPO_URL")
  validate_git_repository_source "$REPO_URL" "$REPO_REF"
}

collect_build_secrets() {
  if [[ $INCLUDE_SECRETS == auto ]]; then
    prompt_boolean INCLUDE_SECRETS 'Include an encrypted bundle containing installation credentials?' false
  fi
  bool_true "$INCLUDE_SECRETS" || return 0

  TEMP_ROOT=${TEMP_ROOT:-$(mktemp -d "$(safe_runtime_dir)/archws-usb-build.XXXXXX")}
  chmod 0700 "$TEMP_ROOT"
  ENCRYPTED_BUNDLE="$TEMP_ROOT/install-secrets.gpg"
  local -a args=(create --config "$CONFIG_FILE" --output "$ENCRYPTED_BUNDLE")
  if [[ -n $SECURE_FILE ]]; then
    args+=(--input "$SECURE_FILE")
  fi
  "$REPO_ROOT/usb/secrets.sh" "${args[@]}"
  load_config "$CONFIG_FILE"
  validate_config runtime
}

prepare_media_config() {
  local hide_username=${1:-$INCLUDE_SECRETS}
  TEMP_ROOT=${TEMP_ROOT:-$(mktemp -d "$(safe_runtime_dir)/archws-usb-build.XXXXXX")}
  chmod 0700 "$TEMP_ROOT"
  MEDIA_CONFIG="$TEMP_ROOT/install.conf"
  cp "$CONFIG_FILE" "$MEDIA_CONFIG"
  chmod 0600 "$MEDIA_CONFIG"
  set_shell_config_value "$MEDIA_CONFIG" LUKS_PASSPHRASE_FILE ""
  set_shell_config_value "$MEDIA_CONFIG" USER_PASSWORD_FILE ""
  set_shell_config_value "$MEDIA_CONFIG" TPM_PIN_FILE ""
  if bool_true "$hide_username"; then
    # The real username is part of the encrypted bundle. Avoid duplicating it in
    # plaintext configuration on the ISO and data partition.
    set_shell_config_value "$MEDIA_CONFIG" USERNAME archuser
  fi
}

prompt_for_device() {
  if [[ -z $DEVICE ]]; then
    printf '\nRemovable and external disks:\n'
    lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,RM,TYPE
    printf '\n'
    prompt_with_default DEVICE 'Whole USB device to erase, such as /dev/sdb' ''
  fi
  DEVICE=$(readlink -f "$DEVICE")
  [[ -b $DEVICE ]] || die "USB target is not a block device: $DEVICE"
  [[ $(lsblk -dnro TYPE "$DEVICE") == disk ]] || die "USB target is not a whole disk: $DEVICE"

  selected_device_backs_source() {
    local source=$1 canonical ancestor
    source=${source%%\[*}
    canonical=$(readlink -f "$source" 2>/dev/null || true)
    [[ -n $canonical && -b $canonical ]] || return 1
    while IFS= read -r ancestor; do
      [[ -n $ancestor ]] || continue
      if [[ $(readlink -f "$ancestor") == "$DEVICE" ]]; then
        return 0
      fi
    done < <(lsblk -srnpo NAME "$canonical" 2>/dev/null || true)
    return 1
  }

  selected_device_backs_path() {
    local path=$1 source
    [[ -e $path ]] || return 1
    source=$(findmnt -nro SOURCE --target "$path" 2>/dev/null || true)
    [[ -n $source ]] || return 1
    selected_device_backs_source "$source"
  }

  local protected_path swap_source size_bytes
  for protected_path in / /boot /efi /home /var /usr /opt; do
    if selected_device_backs_path "$protected_path"; then
      die "Refusing to overwrite $DEVICE because it backs the running system path $protected_path."
    fi
  done
  for protected_path in "$REPO_ROOT" "$CONFIG_FILE" "$CUSTOM_ISO" "$SECURE_FILE"; do
    [[ -n $protected_path ]] || continue
    if selected_device_backs_path "$protected_path"; then
      die "Refusing to overwrite $DEVICE because it contains required build input: $protected_path"
    fi
  done
  while IFS= read -r swap_source; do
    [[ -n $swap_source ]] || continue
    if selected_device_backs_source "$swap_source"; then
      die "Refusing to overwrite $DEVICE while it contains active swap. Disable it with swapoff first."
    fi
  done < <(swapon --show=NAME --noheadings --raw 2>/dev/null || true)

  size_bytes=$(lsblk -bdnro SIZE "$DEVICE")
  ((size_bytes >= 8 * 1024 * 1024 * 1024)) \
    || die 'An 8 GiB or larger USB is required; 16 GiB or larger is recommended for the full offline cache.'
  if ((size_bytes < 16 * 1024 * 1024 * 1024)); then
    warn 'This USB is smaller than 16 GiB. The official ISO plus complete package cache may exhaust the writable partition.'
  fi
}

build_commit() {
  local commit
  commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)
  if [[ -z $commit ]]; then
    printf source-archive
  elif ! git -C "$REPO_ROOT" diff --quiet HEAD -- \
    || ! git -C "$REPO_ROOT" diff --cached --quiet HEAD -- \
    || [[ -n $(git -C "$REPO_ROOT" ls-files --others --exclude-standard) ]]; then
    printf '%s-dirty' "$commit"
  else
    printf '%s' "$commit"
  fi
}

prepare_archiso_profile() {
  local releng=/usr/share/archiso/configs/releng
  local profile="$WORK_DIR/profile"
  [[ -d $releng ]] || die "ArchISO releng profile not found: $releng"
  WORK_PREPARED=true
  sudo rm -rf "$WORK_DIR"
  mkdir -p "$profile" "$OUTPUT_DIR"
  rsync -a "$releng/" "$profile/"

  mkdir -p \
    "$profile/airootfs/opt/arch-workstation-embedded" \
    "$profile/airootfs/etc/arch-workstation-media" \
    "$profile/airootfs/usr/local/bin" \
    "$profile/airootfs/root"
  copy_tracked_repository "$REPO_ROOT" "$profile/airootfs/opt/arch-workstation-embedded"
  prepare_project_tree "$profile/airootfs/opt/arch-workstation-embedded" "$REQUIRED_USB_API_VERSION" \
    || die "The embedded project snapshot failed USB API $REQUIRED_USB_API_VERSION validation."
  printf '%s\n' "$(build_commit)" > "$profile/airootfs/opt/arch-workstation-embedded/BUILD_COMMIT"
  install -m 0600 "$MEDIA_CONFIG" "$profile/airootfs/etc/arch-workstation-media/install.conf"
  write_media_environment \
    "$profile/airootfs/etc/arch-workstation-media/media.env" \
    "$REPO_URL" "$REPO_REF" "$VERSION" "$(build_commit)"
  install -m 0755 "$REPO_ROOT/usb/live/archws-live" "$profile/airootfs/usr/local/bin/archws"
  ln -s archws "$profile/airootfs/usr/local/bin/archws-live"

  cat >> "$profile/airootfs/root/.zlogin" <<'EOF_ZLOGIN'

# arch-workstation custom media launcher. Failure returns to the normal root shell.
if [[ -z ${ARCHWS_LAUNCH_ATTEMPTED:-} && $(tty 2>/dev/null) == /dev/tty1 ]]; then
  export ARCHWS_LAUNCH_ATTEMPTED=1
  /usr/local/bin/archws || printf '\narchws exited with an error; the live root shell remains available.\n' >&2
fi
EOF_ZLOGIN

  cat > "$profile/airootfs/etc/motd" <<'EOF_MOTD'
Arch Workstation recovery/install media.
Run `archws` at any time to open the project launcher.
EOF_MOTD

  cat >> "$profile/packages.x86_64" <<'EOF_PACKAGES'
btrfs-progs
cryptsetup
curl
dosfstools
e2fsprogs
efibootmgr
git
gnupg
gptfdisk
iwd
jq
networkmanager
pacman-contrib
rsync
sbctl
tpm2-tools
util-linux
vim
EOF_PACKAGES
  sort -u -o "$profile/packages.x86_64" "$profile/packages.x86_64"

  sed -i 's/^iso_name=.*/iso_name="arch-workstation"/' "$profile/profiledef.sh"
  sed -i "s/^iso_label=.*/iso_label=\"ARCHWS_$(date +%Y%m%d)\"/" "$profile/profiledef.sh"
  sed -i 's/^iso_publisher=.*/iso_publisher="arch-workstation project"/' "$profile/profiledef.sh"
  sed -i 's|^iso_application=.*|iso_application="Arch Workstation live installer"|' "$profile/profiledef.sh"
  cat >> "$profile/profiledef.sh" <<'EOF_PERMS'

# Added by arch-workstation USB builder.
file_permissions["/usr/local/bin/archws"]="0:0:755"
file_permissions["/etc/arch-workstation-media/install.conf"]="0:0:600"
EOF_PERMS

  find "$profile/airootfs/opt/arch-workstation-embedded" -type f -name '*.sh' -exec chmod 0755 {} +
  chmod 0755 \
    "$profile/airootfs/opt/arch-workstation-embedded/install.sh" \
    "$profile/airootfs/opt/arch-workstation-embedded/start.sh" \
    "$profile/airootfs/opt/arch-workstation-embedded/archctl" \
    "$profile/airootfs/opt/arch-workstation-embedded/build-usb.sh"
}

build_iso() {
  prepare_archiso_profile
  info 'Building the custom ArchISO. Package content is resolved from the current Arch repositories.'
  sudo mkarchiso -v -w "$WORK_DIR/mkarchiso" -o "$OUTPUT_DIR" "$WORK_DIR/profile"
  CUSTOM_ISO=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'arch-workstation-*.iso' -printf '%T@ %p\n' \
    | sort -nr | head -n 1 | cut -d' ' -f2-)
  [[ -s $CUSTOM_ISO ]] || die 'mkarchiso completed without producing an arch-workstation ISO.'
  sudo chown "$(id -u):$(id -g)" "$CUSTOM_ISO"
  sha256sum "$CUSTOM_ISO" > "${CUSTOM_ISO}.sha256"
  success "Custom ArchISO built: $CUSTOM_ISO"
}

unmount_device_children() {
  local mountpoint
  while IFS= read -r mountpoint; do
    [[ -n $mountpoint ]] || continue
    sudo umount "$mountpoint"
  done < <(lsblk -nrpo MOUNTPOINTS "$DEVICE" | awk 'NF' | sort -r)
}

create_data_partition() {
  local partition_table candidate
  local -a existing_partitions=()

  info 'Creating the persistent ARCHWS_DATA partition in the unused space after the hybrid ISO.'
  partition_table=$(lsblk -dnro PTTYPE "$DEVICE" 2>/dev/null || true)
  [[ $partition_table == gpt || $partition_table == dos ]] \
    || die "The written ArchISO has an unsupported partition-table type: ${partition_table:-unknown}."

  mapfile -t existing_partitions < <(lsblk -nrpo NAME,TYPE "$DEVICE" | awk '$2 == "part" {print $1}')

  # ArchISO images are ISOHybrid media. GPT-aware variants retain their backup
  # header at the end of the image rather than the end of the larger USB. Use
  # util-linux's explicit relocation operation before appending a partition.
  # For DOS/MBR ISOHybrid layouts, append directly to the recognised MBR table.
  if [[ $partition_table == gpt ]]; then
    sudo sfdisk --lock --relocate gpt-bak-std "$DEVICE"
    printf 'type=L, name="%s"\n' "$USB_MEDIA_LABEL" \
      | sudo sfdisk --lock --append --wipe never --wipe-partitions never "$DEVICE"
  else
    printf 'type=L\n' \
      | sudo sfdisk --lock --append --wipe never --wipe-partitions never "$DEVICE"
  fi

  sudo partprobe "$DEVICE" || true
  sudo udevadm settle

  DATA_PART=''
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    if ! printf '%s\n' "${existing_partitions[@]}" | grep -Fxq -- "$candidate"; then
      DATA_PART=$candidate
      break
    fi
  done < <(lsblk -nrpo NAME,TYPE "$DEVICE" | awk '$2 == "part" {print $1}')

  [[ -n $DATA_PART && -b $DATA_PART ]] \
    || die 'The new ARCHWS_DATA partition did not appear after appending it to the ISOHybrid partition table.'
  sudo umount "$DATA_PART" 2>/dev/null || true
  sudo mkfs.ext4 -F -L "$USB_MEDIA_LABEL" "$DATA_PART"
  sudo udevadm settle

  # A filesystem label is portable across both GPT and DOS ISOHybrid layouts.
  [[ $(lsblk -dnro LABEL "$DATA_PART" 2>/dev/null || true) == "$USB_MEDIA_LABEL" ]] \
    || die 'The persistent partition was created but its ARCHWS_DATA filesystem label could not be verified.'
}

mount_data_partition() {
  [[ -n $DATA_PART ]] || DATA_PART=$(find_media_partition "$DEVICE" || true)
  [[ -n $DATA_PART ]] || die "No $USB_MEDIA_LABEL partition was found on $DEVICE."
  MOUNT_DIR=$(mktemp -d /tmp/archws-media.XXXXXX)
  sudo mount "$DATA_PART" "$MOUNT_DIR"
}

populate_media() {
  local media_root="$MOUNT_DIR/$USB_MEDIA_DIR_NAME"
  sudo mkdir -p "$media_root"/{cache/archiso/custom,cache/pacman/pkg,cache/repo,config,logs,secure,state}
  sudo install -m 0600 "$MEDIA_CONFIG" "$media_root/config/install.conf"
  local env_temp
  env_temp=$(mktemp)
  write_media_environment "$env_temp" "$REPO_URL" "$REPO_REF" "$VERSION" "$(build_commit)"
  sudo install -m 0644 "$env_temp" "$media_root/media.env"
  rm -f "$env_temp"

  if [[ -n $ENCRYPTED_BUNDLE ]]; then
    sudo install -m 0600 "$ENCRYPTED_BUNDLE" "$media_root/secure/install-secrets.gpg"
    sudo install -m 0644 "${ENCRYPTED_BUNDLE}.meta" "$media_root/secure/install-secrets.gpg.meta"
  else
    sudo rm -f "$media_root/secure/install-secrets.gpg" "$media_root/secure/install-secrets.gpg.meta"
  fi

  if [[ -n $CUSTOM_ISO && -s $CUSTOM_ISO ]]; then
    sudo install -m 0644 "$CUSTOM_ISO" "$media_root/cache/archiso/custom/$(basename -- "$CUSTOM_ISO")"
    sudo install -m 0644 "${CUSTOM_ISO}.sha256" "$media_root/cache/archiso/custom/$(basename -- "${CUSTOM_ISO}.sha256")"
  fi

  if bool_true "$REFRESH_CACHE"; then
    sudo "$REPO_ROOT/usb/cache.sh" \
      --cache-root "$media_root/cache" \
      --config "$media_root/config/install.conf" \
      --source-repo "$REPO_ROOT" \
      --repo-url "$REPO_URL" \
      --repo-ref "$REPO_REF"
  else
    sudo "$REPO_ROOT/usb/cache.sh" \
      --cache-root "$media_root/cache" \
      --config "$media_root/config/install.conf" \
      --source-repo "$REPO_ROOT" \
      --repo-url "$REPO_URL" \
      --repo-ref "$REPO_REF" \
      --repo-only
  fi

  date --iso-8601=seconds | sudo tee "$media_root/state/media-built-at" >/dev/null
  sudo sync
  success "Persistent media populated at $media_root"
}

verify_persistent_media() {
  local verify_mount media_root expected actual custom_iso_copy custom_sum
  [[ -n $DATA_PART && -b $DATA_PART ]] || die 'Persistent media verification has no data partition.'

  info 'Checking the persistent filesystem and reading back its critical cache metadata.'
  sudo e2fsck -f -n "$DATA_PART"
  verify_mount=$(mktemp -d /tmp/archws-media-verify.XXXXXX)
  MOUNT_DIR=$verify_mount
  sudo mount -o ro "$DATA_PART" "$verify_mount"
  media_root="$verify_mount/$USB_MEDIA_DIR_NAME"

  sudo test -r "$media_root/config/install.conf" || die 'Persistent configuration was not readable after USB write.'
  [[ -r $media_root/media.env ]] || die 'Persistent media metadata was not readable after USB write.'
  [[ -s $media_root/cache/repo/project.bundle ]] || die 'Persistent repository bundle was not readable after USB write.'
  sudo git --git-dir="$media_root/cache/repo/mirror.git" \
    bundle verify "$media_root/cache/repo/project.bundle" >/dev/null

  local bundle_checkout
  bundle_checkout=$(mktemp -d /tmp/archws-bundle-verify.XXXXXX)
  git clone -q -- "$media_root/cache/repo/project.bundle" "$bundle_checkout/project" \
    || die 'The persistent repository bundle verified structurally but could not be cloned.'
  prepare_project_tree "$bundle_checkout/project" "$REQUIRED_USB_API_VERSION" \
    || die "The persistent repository bundle does not contain a usable USB API $REQUIRED_USB_API_VERSION project."
  rm -rf "$bundle_checkout"

  custom_iso_copy=$(find "$media_root/cache/archiso/custom" -maxdepth 1 -type f -name '*.iso' -print -quit 2>/dev/null || true)
  if [[ -n $custom_iso_copy ]]; then
    custom_sum="${custom_iso_copy}.sha256"
    [[ -r $custom_sum ]] || die 'The persistent custom-ISO checksum file is missing.'
    expected=$(awk '{print $1; exit}' "$custom_sum")
    actual=$(sudo sha256sum "$custom_iso_copy" | awk '{print $1}')
    [[ -n $expected && $expected == "$actual" ]] || die 'The custom ISO copy on ARCHWS_DATA failed checksum verification.'
  fi

  if [[ -e $media_root/secure/install-secrets.gpg ]]; then
    sudo "$REPO_ROOT/usb/secrets.sh" inspect --input "$media_root/secure/install-secrets.gpg" >/dev/null
  fi

  sudo umount "$verify_mount"
  rmdir "$verify_mount"
  MOUNT_DIR=''
  success 'Persistent USB filesystem, project bundle, metadata, and optional encrypted bundle read back successfully.'
}

write_usb() {
  prompt_for_device
  printf '\nUSB selected for complete erasure:\n'
  lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN "$DEVICE"
  printf '\n'
  local expected="WRITE $DEVICE" response
  if bool_true "$ASSUME_YES"; then
    response=$expected
  else
    warn "All existing data and partitions on $DEVICE will be destroyed."
    read -r -p "Type '$expected' to continue: " response
  fi
  [[ $response == "$expected" ]] || die 'USB write was not confirmed.'

  unmount_device_children
  info 'Removing stale filesystem and partition-table signatures from the USB.'
  sudo sgdisk --zap-all "$DEVICE" >/dev/null 2>&1 || true
  sudo wipefs --all --force "$DEVICE"
  sudo partprobe "$DEVICE" || true
  sudo udevadm settle
  info "Writing $(basename -- "$CUSTOM_ISO") to $DEVICE."
  sudo dd if="$CUSTOM_ISO" of="$DEVICE" bs=16M status=progress conv=fsync
  sudo sync
  local iso_size
  iso_size=$(stat -c '%s' "$CUSTOM_ISO")
  info 'Comparing the ISO-sized region of the USB with the generated image.'
  sudo cmp -n "$iso_size" "$CUSTOM_ISO" "$DEVICE"
  create_data_partition
  mount_data_partition
  populate_media
  sudo umount "$MOUNT_DIR"
  rmdir "$MOUNT_DIR"
  MOUNT_DIR=''
  verify_persistent_media
  success "USB build completed and verified: $DEVICE"
}

refresh_existing_usb() {
  prompt_for_device
  DATA_PART=$(find_media_partition "$DEVICE" || true)
  [[ -n $DATA_PART ]] || die "No existing $USB_MEDIA_LABEL partition was found on $DEVICE. Build a v$VERSION USB normally before using --refresh-only."
  unmount_device_children
  mount_data_partition

  local media_root="$MOUNT_DIR/$USB_MEDIA_DIR_NAME"
  local existing_bundle=false update_media_config=false
  sudo mkdir -p "$media_root"/{cache,config,logs,secure,state}
  sudo test -s "$media_root/secure/install-secrets.gpg" && existing_bundle=true

  TEMP_ROOT=${TEMP_ROOT:-$(mktemp -d "$(safe_runtime_dir)/archws-usb-refresh.XXXXXX")}
  chmod 0700 "$TEMP_ROOT"

  if bool_true "$CONFIG_ACTION_EXPLICIT"; then
    ensure_configuration
    update_media_config=true
  elif sudo test -r "$media_root/config/install.conf"; then
    CONFIG_FILE="$TEMP_ROOT/existing-install.conf"
    sudo cat "$media_root/config/install.conf" > "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE"
    load_config "$CONFIG_FILE"
    validate_config runtime
    info 'Preserving the installation configuration already stored on the USB.'
  else
    warn 'The USB has no persistent installation configuration; creating one from this checkout.'
    ensure_configuration
    update_media_config=true
  fi

  if sudo test -r "$media_root/media.env"; then
    local existing_media_env="$TEMP_ROOT/existing-media.env"
    sudo cat "$media_root/media.env" > "$existing_media_env"
    chmod 0600 "$existing_media_env"
    read_media_environment "$existing_media_env"
    if ! bool_true "$REPO_URL_EXPLICIT"; then
      REPO_URL=${ARCHWS_REPO_URL:-$REPO_URL}
    fi
    if ! bool_true "$REPO_REF_EXPLICIT"; then
      REPO_REF=${ARCHWS_REPO_REF:-$REPO_REF}
    fi
  fi
  detect_repository_source

  if bool_true "$SECRETS_ACTION_EXPLICIT"; then
    collect_build_secrets
    update_media_config=true
  fi

  local bundle_after_refresh=$existing_bundle
  if bool_true "$SECRETS_ACTION_EXPLICIT"; then
    if bool_true "$INCLUDE_SECRETS"; then
      bundle_after_refresh=true
    else
      bundle_after_refresh=false
    fi
  fi

  # A USB built with an encrypted bundle intentionally stores a placeholder
  # username in plaintext. Refuse to remove that bundle unless the caller also
  # supplies a real plaintext username through guided/config-file changes.
  if bool_true "$SECRETS_ACTION_EXPLICIT" \
    && ! bool_true "$INCLUDE_SECRETS" \
    && bool_true "$existing_bundle" \
    && [[ $USERNAME == archuser ]] \
    && ! bool_true "$CONFIG_ACTION_EXPLICIT"; then
    die '--no-secrets would leave the placeholder username "archuser" in the USB configuration. Add --configure or --set USERNAME=youruser when removing the encrypted bundle.'
  fi

  if bool_true "$update_media_config"; then
    prepare_media_config "$bundle_after_refresh"
    sudo install -m 0600 "$MEDIA_CONFIG" "$media_root/config/install.conf"
  else
    MEDIA_CONFIG="$CONFIG_FILE"
  fi

  local env_temp
  env_temp=$(mktemp)
  write_media_environment "$env_temp" "$REPO_URL" "$REPO_REF" "$VERSION" "$(build_commit)"
  sudo install -m 0644 "$env_temp" "$media_root/media.env"
  rm -f "$env_temp"

  if bool_true "$SECRETS_ACTION_EXPLICIT"; then
    if [[ -n $ENCRYPTED_BUNDLE ]]; then
      sudo install -m 0600 "$ENCRYPTED_BUNDLE" "$media_root/secure/install-secrets.gpg"
      sudo install -m 0644 "${ENCRYPTED_BUNDLE}.meta" "$media_root/secure/install-secrets.gpg.meta"
    else
      sudo rm -f "$media_root/secure/install-secrets.gpg" "$media_root/secure/install-secrets.gpg.meta"
    fi
  else
    info 'Preserving the encrypted credential bundle currently stored on the USB.'
  fi

  sudo "$REPO_ROOT/usb/cache.sh" \
    --cache-root "$media_root/cache" \
    --config "$media_root/config/install.conf" \
    --source-repo "$REPO_ROOT" \
    --repo-url "$REPO_URL" \
    --repo-ref "$REPO_REF"
  date --iso-8601=seconds | sudo tee "$media_root/state/last-host-refresh" >/dev/null
  sudo sync
  sudo umount "$MOUNT_DIR"
  rmdir "$MOUNT_DIR"
  MOUNT_DIR=''
  verify_persistent_media
  success "Existing USB cache refreshed without reinstalling or rewriting its boot image: $DEVICE"
}

ensure_builder_packages
info 'Normalising project line endings and executable permissions before creating USB snapshots.'
prepare_project_tree "$REPO_ROOT" "$REQUIRED_USB_API_VERSION" \
  || die "The builder checkout is incomplete or incompatible with USB API $REQUIRED_USB_API_VERSION."
if bool_true "$REFRESH_ONLY"; then
  refresh_existing_usb
  trap - EXIT
  cleanup
  exit 0
fi

ensure_configuration
detect_repository_source
collect_build_secrets
prepare_media_config
build_iso
if bool_true "$WRITE_USB"; then
  write_usb
else
  success 'ISO-only build complete; no block device was modified.'
fi

trap - EXIT
cleanup
