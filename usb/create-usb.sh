#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/usb-common.sh
source "$REPO_ROOT/usb/lib/usb-common.sh"

DISK=""
REPO_URL=""
REPO_REF=""
INSTALL_CONFIG="$REPO_ROOT/profiles/t480.conf"
USB_CONFIG="$REPO_ROOT/config/usb.conf.example"
REPO_CONFIG_PATH=""
WITH_OFFLINE_PACKAGES=false
ALLOW_NON_REMOVABLE=false
ARCH_MIRROR="https://geo.mirror.pkgbuild.com"
MOUNT_DIR=""
PARTITION=""

usage() {
  cat <<'USAGE'
Usage: sudo ./usb/create-usb.sh --disk /dev/disk/by-id/usb-... [options]

Required:
  --disk PATH                 Whole USB disk; every partition will be erased

Options:
  --repo-url URL              Public GitHub repository used for online updates
  --repo-ref REF              Branch or tag; overrides usb.conf
  --install-config PATH       Local emergency profile copied to the USB
  --usb-config PATH           USB update-policy file
  --repo-config-path PATH     Profile path within Git; overrides usb.conf
  --with-offline-packages     Build complete official/AUR package caches now
  --allow-non-removable       Permit a disk whose kernel RM flag is zero
  -h, --help                  Show this help

The command creates one FAT32 UEFI partition with two independently bootable
Arch live slots, current/previous repository snapshots, and cache space.
USAGE
}

while (($#)); do
  case "$1" in
    --disk) [[ $# -ge 2 ]] || usb_die "--disk requires a path"; DISK=$2; shift 2 ;;
    --repo-url) [[ $# -ge 2 ]] || usb_die "--repo-url requires a value"; REPO_URL=$2; shift 2 ;;
    --repo-ref) [[ $# -ge 2 ]] || usb_die "--repo-ref requires a value"; REPO_REF=$2; shift 2 ;;
    --install-config) [[ $# -ge 2 ]] || usb_die "--install-config requires a path"; INSTALL_CONFIG=$2; shift 2 ;;
    --usb-config) [[ $# -ge 2 ]] || usb_die "--usb-config requires a path"; USB_CONFIG=$2; shift 2 ;;
    --repo-config-path) [[ $# -ge 2 ]] || usb_die "--repo-config-path requires a value"; REPO_CONFIG_PATH=$2; shift 2 ;;
    --with-offline-packages) WITH_OFFLINE_PACKAGES=true; shift ;;
    --allow-non-removable) ALLOW_NON_REMOVABLE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usb_die "Unknown option: $1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || usb_die "USB creation must run as root."
[[ -n $DISK ]] || { usage >&2; usb_die "--disk is required."; }
[[ -r $INSTALL_CONFIG ]] || usb_die "Install configuration not found: $INSTALL_CONFIG"
[[ -r $USB_CONFIG ]] || usb_die "USB configuration not found: $USB_CONFIG"
if [[ -n $REPO_CONFIG_PATH ]]; then
  [[ $REPO_CONFIG_PATH != /* && $REPO_CONFIG_PATH != *'..'* ]] \
    || usb_die "--repo-config-path must be a safe path relative to the repository root."
fi
usb_require_commands awk blkid bsdtar curl findmnt grub-install lsblk mkfs.fat mount \
  partprobe readlink sgdisk sha256sum swapon tar udevadm umount wipefs

DISK=$(readlink -f "$DISK")
[[ -b $DISK ]] || usb_die "Not a block device: $DISK"
[[ $(lsblk -dn -o TYPE "$DISK") == disk ]] || usb_die "Target must be a whole disk: $DISK"
disk_size_bytes=$(lsblk -bdn -o SIZE "$DISK")
minimum_size_bytes=$((8 * 1024 * 1024 * 1024))
if usb_bool_true "$WITH_OFFLINE_PACKAGES"; then
  minimum_size_bytes=$((32 * 1024 * 1024 * 1024))
fi
((disk_size_bytes >= minimum_size_bytes)) \
  || usb_die "$DISK is too small for this mode. Use at least $((minimum_size_bytes / 1024 / 1024 / 1024)) GiB."
if ! usb_bool_true "$ALLOW_NON_REMOVABLE" && [[ $(lsblk -dn -o RM "$DISK") != 1 ]]; then
  usb_die "$DISK is not marked removable. Use --allow-non-removable only after checking its model and serial."
fi

root_source=$(findmnt -rn -o SOURCE / | head -n 1)
target_name=$(basename -- "$DISK")
if lsblk -sn -o NAME "$root_source" 2>/dev/null | grep -Fxq "$target_name"; then
  usb_die "Refusing to erase the disk that contains the running root filesystem."
fi

while IFS= read -r swap_source; do
  [[ -n $swap_source ]] || continue
  swap_source=$(readlink -f "$swap_source")
  if lsblk -nrpo NAME "$DISK" | grep -Fxq "$swap_source"; then
    usb_die "Active swap exists on $swap_source. Disable it before creating the USB."
  fi
done < <(swapon --show=NAME --noheadings --raw 2>/dev/null || true)

printf '\nTarget USB details:\n'
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN,RM "$DISK"
printf '\nExisting layout:\n'
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS "$DISK"
printf '\n'
read -r -p "Type 'ERASE $DISK' to create the installer USB: " confirmation
[[ $confirmation == "ERASE $DISK" ]] || usb_die "USB erasure was not confirmed."

partition_path() {
  if [[ $1 =~ [0-9]$ ]]; then printf '%sp1\n' "$1"; else printf '%s1\n' "$1"; fi
}

cleanup() {
  local code=$?
  if [[ -n ${MOUNT_DIR:-} ]] && findmnt -rn "$MOUNT_DIR" >/dev/null 2>&1; then
    umount "$MOUNT_DIR" || true
  fi
  [[ -z ${MOUNT_DIR:-} ]] || rmdir "$MOUNT_DIR" 2>/dev/null || true
  exit "$code"
}
trap cleanup EXIT

while IFS= read -r mountpoint; do
  [[ -n $mountpoint ]] || continue
  umount "$mountpoint"
done < <(lsblk -nr -o MOUNTPOINTS "$DISK" | awk 'NF')

wipefs --all --force "$DISK"
sgdisk --zap-all "$DISK"
sgdisk --new=1:0:0 --typecode=1:ef00 --change-name=1:MASON_ARCH "$DISK"
partprobe "$DISK"
udevadm settle
PARTITION=$(partition_path "$DISK")
for _ in {1..50}; do
  [[ -b $PARTITION ]] && break
  sleep 0.1
done
[[ -b $PARTITION ]] || usb_die "USB partition did not appear: $PARTITION"
mkfs.fat -F 32 -n MASON_ARCH "$PARTITION"

MOUNT_DIR=$(mktemp -d)
mount "$PARTITION" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR/boot" "$MOUNT_DIR/EFI"
usb_info "Installing the removable x86-64 UEFI GRUB loader."
grub-install \
  --target=x86_64-efi \
  --efi-directory="$MOUNT_DIR" \
  --boot-directory="$MOUNT_DIR/boot" \
  --removable \
  --no-nvram \
  --recheck
install -Dm0644 "$REPO_ROOT/usb/grub/grub.cfg" "$MOUNT_DIR/boot/grub/grub.cfg"

LAYOUT=$(usb_layout_dir "$MOUNT_DIR")
mkdir -p \
  "$LAYOUT/config" \
  "$LAYOUT/runtime" \
  "$LAYOUT/cache/repository" \
  "$LAYOUT/cache/downloads" \
  "$LAYOUT/state"
printf '%s\n' "$USB_LAYOUT_VERSION" > "$LAYOUT/.layout-version"
install -m 0600 "$INSTALL_CONFIG" "$LAYOUT/config/install.conf"
install -m 0644 "$USB_CONFIG" "$LAYOUT/config/usb.conf"
{
  [[ -z $REPO_URL ]] || printf '\nREPO_URL=%q\n' "$REPO_URL"
  [[ -z $REPO_REF ]] || printf 'REPO_REF=%q\n' "$REPO_REF"
  [[ -z $REPO_CONFIG_PATH ]] || printf 'INSTALL_CONFIG_REPO_PATH=%q\n' "$REPO_CONFIG_PATH"
} >> "$LAYOUT/config/usb.conf"
usb_load_config "$LAYOUT/config/usb.conf"
install -m 0755 "$REPO_ROOT/usb/start.sh" "$LAYOUT/start.sh"
install -m 0644 "$REPO_ROOT/usb/lib/usb-common.sh" "$LAYOUT/runtime/usb-common.sh"

snapshot_archive="$LAYOUT/cache/repository/current.tar.gz"
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  snapshot_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
  [[ -z $(git -C "$REPO_ROOT" status --porcelain) ]] || snapshot_commit+="-dirty"
  (
    cd "$REPO_ROOT"
    git ls-files -z | tar --null --files-from=- -czf "$snapshot_archive"
  )
else
  snapshot_commit=source-tree
  tar -C "$REPO_ROOT" \
    --exclude=.git \
    --exclude=config/install.conf \
    --exclude=config/usb.conf \
    --exclude='*.secret' \
    --exclude='*.key' \
    --exclude='*.pem' \
    --exclude='.cache' \
    --exclude='.usb-build' \
    --exclude='build' \
    --exclude='dist' \
    --exclude='.idea' \
    --exclude='.vscode' \
    --exclude='*.img' \
    --exclude='*.iso' \
    --exclude='*.log' \
    --exclude='*.zip' \
    --exclude='*.tar.gz' \
    -czf "$snapshot_archive" .
fi
printf '%s  current.tar.gz\n' "$(sha256sum "$snapshot_archive" | awk '{print $1}')" \
  > "$LAYOUT/cache/repository/current.sha256"
printf '%s\n' "$snapshot_commit" > "$LAYOUT/cache/repository/current.commit"
cp -f "$snapshot_archive" "$LAYOUT/cache/repository/previous.tar.gz"
printf '%s  previous.tar.gz\n' \
  "$(sha256sum "$LAYOUT/cache/repository/previous.tar.gz" | awk '{print $1}')" \
  > "$LAYOUT/cache/repository/previous.sha256"
printf '%s\n' "$snapshot_commit" > "$LAYOUT/cache/repository/previous.commit"

ISO="$LAYOUT/cache/downloads/archlinux-x86_64.iso"
SIG="$ISO.sig"
SUMS="$LAYOUT/cache/downloads/sha256sums.txt"
usb_info "Downloading the current official Arch image."
curl -fL --retry 3 --continue-at - "$ARCH_MIRROR/iso/latest/archlinux-x86_64.iso" -o "$ISO.part"
mv -f "$ISO.part" "$ISO"
curl -fL --retry 3 "$ARCH_MIRROR/iso/latest/archlinux-x86_64.iso.sig" -o "$SIG"
curl -fL --retry 3 "https://archlinux.org/iso/latest/sha256sums.txt" -o "$SUMS"
expected_hash=$(awk '$2 == "archlinux-x86_64.iso" {print $1}' "$SUMS" | head -n 1)
actual_hash=$(sha256sum "$ISO" | awk '{print $1}')
[[ -n $expected_hash && $actual_hash == "$expected_hash" ]] \
  || usb_die "Arch ISO SHA-256 verification failed."
if [[ -r /etc/arch-release ]] && command -v pacman-key >/dev/null 2>&1; then
  pacman-key -v "$SIG" || usb_die "Arch ISO PGP signature verification failed."
  usb_ok "Arch ISO PGP signature and SHA-256 checksum verified."
else
  usb_warn "This is not an Arch host with pacman-key; the ISO was checked against archlinux.org's HTTPS checksum."
  usb_warn "The first live refresh will verify the next image with the Arch keyring."
fi

usb_info "Extracting two independent Arch recovery slots."
bsdtar -xf "$ISO" -C "$MOUNT_DIR" arch
mv "$MOUNT_DIR/arch" "$MOUNT_DIR/arch-a"
mkdir -p "$MOUNT_DIR/arch-b"
cp -r "$MOUNT_DIR/arch-a/." "$MOUNT_DIR/arch-b/"
usb_verify_arch_slot "$MOUNT_DIR" a || usb_die "Arch slot a failed validation."
usb_verify_arch_slot "$MOUNT_DIR" b || usb_die "Arch slot b failed validation."
usb_write_active_slot "$MOUNT_DIR" a

if ! usb_bool_true "$KEEP_DOWNLOADED_ISO"; then
  rm -f "$ISO" "$SIG" "$SUMS"
fi
sync

if usb_bool_true "$WITH_OFFLINE_PACKAGES"; then
  command -v pacman >/dev/null 2>&1 \
    || usb_die "--with-offline-packages requires an Arch host or Arch live environment with pacman."
  bash "$REPO_ROOT/usb/refresh-packages.sh" \
    --usb-root "$MOUNT_DIR" \
    --install-config "$LAYOUT/config/install.conf"
fi

bash "$REPO_ROOT/usb/verify-usb.sh" --usb-root "$MOUNT_DIR"
usb_ok "Self-updating Arch installer USB created on $DISK."
echo "Boot it in UEFI mode with Secure Boot temporarily disabled."
