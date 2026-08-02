#!/usr/bin/env bash

prepare_disk() {
  info "Preparing $DISK."
  wipefs --all --force "$DISK"
  sgdisk --zap-all "$DISK"
  sgdisk --clear \
    --new=1:0:+"${ESP_SIZE_MIB}"M --typecode=1:ef00 --change-name=1:'EFI System' \
    --new=2:0:0 --typecode=2:8309 --change-name=2:'Arch Linux LUKS' \
    "$DISK"
  partprobe "$DISK"
  udevadm settle

  ESP_PART=$(partition_path "$DISK" 1)
  ROOT_PART=$(partition_path "$DISK" 2)
  wait_for_block_device "$ESP_PART"
  wait_for_block_device "$ROOT_PART"

  mkfs.fat -F 32 -n ARCH_EFI "$ESP_PART"

  [[ -n ${INSTALL_LUKS_PASSPHRASE:-} ]] || die "The LUKS passphrase was not collected before disk preparation."
  printf '%s' "$INSTALL_LUKS_PASSPHRASE" | cryptsetup luksFormat \
    --type luks2 --label arch_crypt --batch-mode --key-file - "$ROOT_PART"
  printf '%s' "$INSTALL_LUKS_PASSPHRASE" | cryptsetup open \
    --type luks --key-file - "$ROOT_PART" "$CRYPT_NAME"
  CRYPT_OPENED_BY_INSTALLER=true
  unset INSTALL_LUKS_PASSPHRASE

  LUKS_UUID=$(cryptsetup luksUUID "$ROOT_PART")
  mkfs.btrfs -f -L arch_root "/dev/mapper/$CRYPT_NAME"

  mount "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT"
  TARGET_MOUNTED_BY_INSTALLER=true
  btrfs subvolume create "$INSTALL_ROOT/@"
  btrfs subvolume create "$INSTALL_ROOT/@home"
  btrfs subvolume create "$INSTALL_ROOT/@var_log"
  btrfs subvolume create "$INSTALL_ROOT/@pkg"
  btrfs subvolume create "$INSTALL_ROOT/@snapshots"
  umount "$INSTALL_ROOT"
  TARGET_MOUNTED_BY_INSTALLER=false

  local opts='noatime,compress=zstd:1'
  mount -o "$opts,subvol=@" "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT"
  TARGET_MOUNTED_BY_INSTALLER=true
  mkdir -p \
    "$INSTALL_ROOT/efi" \
    "$INSTALL_ROOT/home" \
    "$INSTALL_ROOT/var/log" \
    "$INSTALL_ROOT/var/cache/pacman/pkg" \
    "$INSTALL_ROOT/.snapshots"
  mount -o "$opts,subvol=@home" "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT/home"
  mount -o "$opts,subvol=@var_log" "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT/var/log"
  mount -o "$opts,subvol=@pkg" "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT/var/cache/pacman/pkg"
  mount -o "$opts,subvol=@snapshots" "/dev/mapper/$CRYPT_NAME" "$INSTALL_ROOT/.snapshots"
  mount "$ESP_PART" "$INSTALL_ROOT/efi"
  chmod 0750 "$INSTALL_ROOT/.snapshots"

  success "Disk, encryption, and Btrfs subvolumes are ready."
}
