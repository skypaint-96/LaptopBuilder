#!/usr/bin/env bash

preflight_install() {
  require_root
  require_commands \
    arch-chroot awk blkid btrfs cryptsetup curl efibootmgr findmnt genfstab \
    lsblk mkfs.btrfs mkfs.fat mount od pacman pacman-conf pacstrap partprobe readlink sgdisk \
    stat swapon timedatectl udevadm umount wipefs

  [[ $(uname -m) == x86_64 ]] || die "Only x86_64 is supported."

  local detected_cpu dmi_identity
  detected_cpu=$(awk -F: '/vendor_id/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' /proc/cpuinfo)
  if [[ $CPU_VENDOR == intel && $detected_cpu != GenuineIntel ]]; then
    warn "CPU_VENDOR=intel but the detected CPU vendor is $detected_cpu."
  elif [[ $CPU_VENDOR == amd && $detected_cpu != AuthenticAMD ]]; then
    warn "CPU_VENDOR=amd but the detected CPU vendor is $detected_cpu."
  fi
  if bool_true "$ENABLE_T480"; then
    dmi_identity="$(cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version 2>/dev/null || true)"
    [[ $dmi_identity == *T480* ]] || warn "The T480 role is enabled, but DMI does not identify a ThinkPad T480."
  fi
  [[ -d /sys/firmware/efi/efivars ]] || die "The Arch ISO was not booted in UEFI mode."

  if ! bool_true "$ALLOW_NON_ARCHISO"; then
    [[ -d /run/archiso ]] || die "Run the destructive installer from the official Arch ISO, or explicitly set ALLOW_NON_ARCHISO=true."
  fi

  [[ -b $DISK ]] || die "Target is not a block device: $DISK"
  [[ $(lsblk -dn -o TYPE "$DISK") == disk ]] || die "Target is not a whole disk: $DISK"

  if findmnt -rn -R "$INSTALL_ROOT" >/dev/null 2>&1; then
    die "Installation mount root $INSTALL_ROOT is already in use. Unmount it before continuing."
  fi
  if cryptsetup status "$CRYPT_NAME" >/dev/null 2>&1; then
    die "Device-mapper name '$CRYPT_NAME' is already active. Close or rename it before continuing."
  fi

  if lsblk -nr -o MOUNTPOINTS "$DISK" | grep -q '[^[:space:]]'; then
    die "A partition on $DISK is mounted. Unmount it before continuing."
  fi

  local swap_device target_device
  while IFS= read -r swap_device; do
    [[ -n $swap_device ]] || continue
    swap_device=$(readlink -f "$swap_device")
    while IFS= read -r target_device; do
      [[ -n $target_device ]] || continue
      if [[ $swap_device == "$target_device" ]]; then
        die "Active swap exists on $swap_device. Disable it with swapoff before continuing."
      fi
    done < <(lsblk -nrpo NAME "$DISK")
  done < <(swapon --show=NAME --noheadings --raw)

  if secure_boot_enabled; then
    die "Secure Boot is currently enabled. This installer requires it disabled while owner keys are enrolled; disable Secure Boot and boot the ISO again."
  fi

  if bool_true "$ENABLE_SECURE_BOOT" && ! setup_mode_enabled; then
    if bool_true "$REQUIRE_SETUP_MODE_AT_INSTALL"; then
      die "Secure Boot Setup Mode is required before installation. In firmware, disable Secure Boot and clear the enrolled Secure Boot keys, then boot the ISO again."
    fi
    warn "Firmware is not in Secure Boot Setup Mode. Owner-key enrollment will require another firmware visit after installation."
  fi

  if bool_true "$ENABLE_TPM"; then
    if [[ ! -e /sys/class/tpm/tpm0 ]]; then
      if bool_true "$REQUIRE_TPM"; then
        die "TPM2 was requested but no TPM device is visible. Enable the security chip in firmware."
      fi
      warn "No TPM device is visible; TPM enrollment will be unavailable."
    fi
  fi

  local source_mode=${ARCHWS_SOURCE_MODE:-live}
  [[ $source_mode == live || $source_mode == offline ]] || die "ARCHWS_SOURCE_MODE must be live or offline."
  INITIAL_INSTALL_SOURCE_MODE=$source_mode
  if [[ $source_mode == live ]]; then
    info "Checking internet connectivity."
    curl --connect-timeout 10 --max-time 30 --retry 2 -fsS https://archlinux.org/ -o /dev/null \
      || die "Unable to reach archlinux.org."
    timedatectl set-ntp true || warn "Could not enable network time synchronisation in the ISO."
  else
    info "Offline source mode selected; using cached repository databases and packages."
    [[ -d /var/lib/pacman/sync ]] || die "Offline pacman databases are not available."
    [[ -n ${ARCHWS_PACKAGE_CACHE_DIR:-} && -d ${ARCHWS_PACKAGE_CACHE_DIR:-} ]] \
      || die "Offline package cache is not available."
  fi

  enable_live_iso_multilib
  verify_live_package_resolution
  if [[ $source_mode == offline ]]; then
    verify_offline_package_payloads
  fi
  verify_aur_package_resolution

  printf '\n'
  print_config_summary
  printf '\nTarget disk details:\n'
  lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN "$DISK"
  printf '\nCurrent target layout:\n'
  lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS "$DISK"
  printf '\n'

  if bool_true "${PREFLIGHT_ONLY:-false}"; then
    success "Preflight checks passed; destructive confirmation was intentionally skipped."
    return 0
  fi

  local expected="ERASE $DISK" response
  if bool_true "$NONINTERACTIVE"; then
    [[ $WIPE_CONFIRMATION == "$expected" ]] || die "NONINTERACTIVE requires WIPE_CONFIRMATION=\"$expected\"."
    [[ -n $LUKS_PASSPHRASE_FILE ]] || die "NONINTERACTIVE requires LUKS_PASSPHRASE_FILE."
    [[ -n $USER_PASSWORD_FILE ]] || die "NONINTERACTIVE requires USER_PASSWORD_FILE."
    if bool_true "$ENABLE_TPM" && bool_true "$TPM_WITH_PIN"; then
      [[ -n $TPM_PIN_FILE ]] || die "NONINTERACTIVE with TPM_WITH_PIN=true requires TPM_PIN_FILE."
    fi
  else
    warn "Every partition and all data on $DISK will be destroyed."
    read -r -p "Type '$expected' to continue: " response
    [[ $response == "$expected" ]] || die "Disk erasure was not confirmed."
  fi

  success "Preflight checks passed."
}
