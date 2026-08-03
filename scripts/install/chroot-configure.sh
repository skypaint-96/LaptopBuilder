#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="/opt/arch-workstation"
CONFIG_FILE=${1:-$REPO_ROOT/config/install.conf}

# shellcheck source=../lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

require_root
load_config "$CONFIG_FILE"
validate_config runtime
# shellcheck source=/dev/null
source /etc/arch-installer/install.env

info "Configuring locale, time, host, and user."
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

sed -i "s/^#${LOCALE//./\\.} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
if ! grep -qxF "$LOCALE UTF-8" /etc/locale.gen; then
  printf '%s UTF-8\n' "$LOCALE" >> /etc/locale.gen
fi
locale-gen
printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf

printf '%s\n' "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOF

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd --create-home --user-group --groups wheel,audio,video,storage,optical --shell /bin/bash "$USERNAME"
fi
cat > /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/10-wheel
visudo --check --file=/etc/sudoers.d/10-wheel >/dev/null
passwd --lock root

info "Configuring pacman and multilib."
sed -i 's/^#Color$/Color/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists$/VerbosePkgLists/' /etc/pacman.conf
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
  sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
elif ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
  printf '\nParallelDownloads = 5\n' >> /etc/pacman.conf
fi
if bool_true "$ENABLE_MULTILIB" && ! pacman-conf --repo-list | grep -qx multilib; then
  temp_conf=$(mktemp)
  awk '
    /^#?\[multilib\]$/ {
      print "[multilib]"
      in_multilib = 1
      found_multilib = 1
      next
    }
    in_multilib && /^#?Include[[:space:]]*=[[:space:]]*\/etc\/pacman\.d\/mirrorlist$/ {
      sub(/^#/, "")
      print
      next
    }
    in_multilib && /^\[/ { in_multilib = 0 }
    { print }
    END {
      if (!found_multilib) {
        print ""
        print "[multilib]"
        print "Include = /etc/pacman.d/mirrorlist"
      }
    }
  ' /etc/pacman.conf > "$temp_conf"
  install -m 0644 "$temp_conf" /etc/pacman.conf
  rm -f "$temp_conf"
fi
if bool_true "$ENABLE_MULTILIB"; then
  pacman-conf --repo-list | grep -qx multilib \
    || die "Could not enable multilib in the installed system."
fi

info "Configuring encrypted early boot and UKIs."
mkdir -p /etc/kernel /efi/EFI/Linux /etc/mkinitcpio.d
crypt_options="luks"
if bool_true "$ENABLE_SSD_TRIM"; then
  crypt_options+=",discard"
fi
cat > /etc/crypttab.initramfs <<EOF
cryptroot UUID=$LUKS_UUID none $crypt_options
EOF
chmod 0600 /etc/crypttab.initramfs

cat > /etc/kernel/cmdline <<EOF
rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet loglevel=3
EOF

case "$GPU_VENDOR" in
  intel) gpu_modules='i915' ;;
  amd) gpu_modules='amdgpu' ;;
  generic) gpu_modules='' ;;
esac
cat > /etc/mkinitcpio.conf <<EOF
MODULES=($gpu_modules)
BINARIES=()
FILES=()
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
COMPRESSION="zstd"
EOF

read -r -a kernel_list <<< "$KERNELS"
for kernel in "${kernel_list[@]}"; do
  cat > "/etc/mkinitcpio.d/${kernel}.preset" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${kernel}"
ALL_cmdline="/etc/kernel/cmdline"
PRESETS=('default')
default_uki="/efi/EFI/Linux/arch-${kernel}.efi"
EOF
done

bootctl --esp-path=/efi --no-variables install
cat > /efi/loader/loader.conf <<'EOF'
default arch-linux.efi
timeout 3
console-mode max
editor no
auto-firmware yes
EOF

mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/90-systemd-boot-update.hook <<'EOF'
[Trigger]
Operation = Upgrade
Type = Package
Target = systemd

[Action]
Description = Updating systemd-boot before the sbctl signing hook...
When = PostTransaction
Exec = /usr/bin/bootctl --esp-path=/efi --no-variables update
EOF

mkinitcpio -P

info "Configuring desktop, networking, audio, Bluetooth, and zram."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-arch-workstation.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF

mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/50-arch-workstation.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
EOF

systemctl enable NetworkManager.service
systemctl enable lightdm.service
systemctl enable systemd-timesyncd.service
if bool_true "$ENABLE_SSD_TRIM"; then
  systemctl enable fstrim.timer
else
  systemctl disable fstrim.timer >/dev/null 2>&1 || true
fi
if bool_true "$ENABLE_BLUETOOTH"; then
  systemctl enable bluetooth.service
else
  systemctl disable bluetooth.service >/dev/null 2>&1 || true
fi
if bool_true "$ENABLE_SSH"; then
  systemctl enable sshd.service
else
  systemctl disable sshd.service >/dev/null 2>&1 || true
fi
systemctl set-default graphical.target

install -d -m 0755 /var/lib/arch-workstation /etc/profile.d
cat > /etc/motd <<'EOF'
Arch base installation is complete.
Run `archctl finish` as the normal user to resume the guided first-boot workflow.
EOF
chmod 0644 /etc/motd

cat > /etc/profile.d/arch-workstation-first-boot.sh <<'EOF'
if [[ $- == *i* && -x /usr/local/bin/archctl && ! -e /var/lib/arch-workstation/complete ]]; then
  printf '%s\n' 'arch-workstation setup is incomplete. Run: archctl finish'
fi
EOF
chmod 0644 /etc/profile.d/arch-workstation-first-boot.sh

ln -sf /opt/arch-workstation/archctl /usr/local/bin/archctl
ln -sf /opt/arch-workstation/start.sh /usr/local/bin/arch-workstation-start
ln -sf /opt/arch-workstation/build-usb.sh /usr/local/bin/arch-workstation-build-usb
chown -R root:root /opt/arch-workstation
chown root:wheel /etc/arch-installer/install.conf
chmod 0640 /etc/arch-installer/install.conf
chmod 0600 /etc/arch-installer/install.env
rm -f /opt/arch-workstation/config/install.conf
ln -s /etc/arch-installer/install.conf /opt/arch-workstation/config/install.conf

success "Chroot configuration completed."
