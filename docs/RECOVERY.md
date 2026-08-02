# Recovery guide

Keep this guide and the repository somewhere other than the laptop. Substitute actual devices from `lsblk`; commands below use the default NVMe layout.

## First response

1. Record the exact failure.
2. Do not clear the TPM, restore firmware keys, reformat or delete LUKS slots impulsively.
3. Confirm the passphrase or recovery key is available.
4. Disconnect unneeded disks before destructive or mount commands.
5. Prefer reversible paths: recovery USB slot, maintenance shell, LTS kernel, passphrase fallback or temporary Secure Boot disablement.

## Installer USB recovery

At the GRUB menu:

- **current cached slot** boots the slot selected after the last successful refresh;
- **recovery slot** boots the other complete Arch environment;
- **maintenance shell** does not start the automated installer.

When a newly refreshed slot fails, boot recovery. The refresh process never overwrites the slot that was running when the update was staged.

From a live shell, inspect and verify:

```bash
cat /run/archiso/bootmnt/MASON-ARCH/state/active-slot.cfg
cat /run/archiso/bootmnt/MASON-ARCH/cache/repository/current.commit 2>/dev/null || true
sudo /run/mason-installer/repo/usb/verify-usb.sh \
  --usb-root /run/archiso/bootmnt
```


If current repository validation fails, startup uses previous automatically. If both fail, rebuild the USB from a known-good clone rather than disabling checks.

At startup, recognised interrupted refresh states are repaired conservatively. A complete `.old` Arch slot or package-cache pair is restored when activation did not finish; a lone complete `.new` Arch slot can be completed; and an invalid selected Arch slot is changed to the other verified slot. Run `verify-usb.sh` after any such recovery warning.

When the USB is read-only, automatic refresh is disabled but cached boot and installation remain available. Do not force writes to a failing device; copy/rebuild it from the Git repository and verify the replacement.

## Boot the installed LTS kernel

Hold **Space** during systemd-boot startup and select `arch-linux-lts.efi`. After booting:

```bash
uname -r
sudo archctl verify
```

## TPM unlock fails

Use the ordinary LUKS passphrase or recovery key. Once booted:

```bash
sudo systemd-cryptenroll /dev/disk/by-uuid/YOUR_LUKS_UUID
sudo cryptsetup luksDump /dev/disk/by-uuid/YOUR_LUKS_UUID
sudo sbctl status
```

Remove only systemd TPM enrollment:

```bash
sudo archctl tpm-remove
```

After confirming Secure Boot state:

```bash
sudo archctl tpm-enroll
```

Reboot and test both paths.

## Secure Boot prevents booting

Temporarily disable Secure Boot without restoring factory keys. Boot the installed system or USB maintenance environment and inspect:

```bash
sudo sbctl status
sudo sbctl verify
bootctl status
```

With the expected owner keys available:

```bash
sudo bootctl --esp-path=/efi update
sudo mkinitcpio -P
sudo sbctl sign-all
sudo sbctl verify
```

Re-enable Secure Boot and test. Restore lost `sbctl` keys only from the protected offline backup. If no key backup exists, establish new owner keys from firmware Setup Mode and re-sign the boot chain; LUKS encryption is separate.

## Chroot from the installer USB

Boot either usable Arch live slot with Secure Boot disabled. Identify devices:

```bash
lsblk -f
```

Open and mount:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}
mount /dev/nvme0n1p1 /mnt/efi
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
arch-chroot /mnt
```

Typical online repair:

```bash
pacman -Syu
bootctl --esp-path=/efi install
mkinitcpio -P
sbctl sign-all
sbctl verify
```

Run signing only when the expected key exists under `/var/lib/sbctl/keys`.

Exit cleanly:

```bash
exit
umount -R /mnt
cryptsetup close cryptroot
reboot
```

## Root snapshot rollback

Snapshots exclude separate home, log, package-cache and snapshot subvolumes. Inspect first:

```bash
sudo snapper -c root list
sudo snapper -c root status OLD..NEW
```

Offline, open LUKS and mount the Btrfs top level:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot
mount -o subvolid=5 /dev/mapper/cryptroot /mnt
btrfs subvolume list /mnt
```

After verifying `/mnt/@snapshots/NUMBER/snapshot`:

```bash
stamp=$(date +%Y%m%d-%H%M%S)
mv /mnt/@ "/mnt/@-broken-$stamp"
btrfs subvolume snapshot /mnt/@snapshots/NUMBER/snapshot /mnt/@
```

Remount the restored layout, chroot, rebuild UKIs and re-sign as applicable before booting. Keep `@-broken-*` until the restored system and personal data have been checked.

## Reinstall

When repair is less trustworthy than rebuilding:

1. recover personal data;
2. boot the current or recovery USB slot;
3. let GitHub refresh the reviewed configuration, or deliberately use the cached snapshot;
4. perform a fresh installation;
5. restore personal data separately;
6. re-enroll Secure Boot and TPM for the new installation.

Do not copy old TPM tokens or LUKS metadata blindly between installations.
