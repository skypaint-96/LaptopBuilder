# Recovery guide

Keep a copy of this guide and the repository somewhere other than the laptop. Recovery commands assume the default disk layout; substitute the actual device from `lsblk`.

## First response checklist

1. Stop and record the exact failure message.
2. Do not clear the TPM, reset Secure Boot keys, reformat, or delete LUKS slots impulsively.
3. Confirm that the LUKS passphrase or offline recovery key is available.
4. Disconnect unneeded external storage before running disk commands.
5. Prefer reversible actions: choose the LTS kernel, use passphrase fallback, or temporarily disable Secure Boot.

## Boot the LTS kernel

systemd-boot normally hides behind a short timeout. Press and hold **Space** during startup to display the menu, then select the `arch-linux-lts.efi` entry.

After booting successfully:

```bash
uname -r
sudo archctl verify
```

Investigate the current kernel or package update before changing the default permanently.

## TPM unlock fails

A PCR mismatch or TPM lockout should fall back to an ordinary LUKS passphrase prompt. Enter the known-good passphrase.

Once booted, inspect the token and Secure Boot state:

```bash
sudo systemd-cryptenroll /dev/disk/by-uuid/YOUR_LUKS_UUID
sudo sbctl status
sudo cryptsetup luksDump /dev/disk/by-uuid/YOUR_LUKS_UUID
```

Remove TPM enrollment without touching passphrase slots:

```bash
sudo archctl tpm-remove
```

After confirming the machine's firmware and Secure Boot state, re-enroll:

```bash
archctl tpm-enroll
```

Reboot and test both TPM/PIN and passphrase paths.

## Secure Boot prevents booting

Temporarily disable Secure Boot in firmware without restoring factory keys. Boot Arch and inspect:

```bash
sudo sbctl status
sudo sbctl verify
bootctl status
```

Refresh and re-sign the complete boot path:

```bash
sudo bootctl --esp-path=/efi update
sudo mkinitcpio -P
sudo sbctl sign-all
sudo sbctl verify
```

Re-enable Secure Boot and test. If the local sbctl key directory has been lost, restore it from the protected offline backup before signing. If no backup exists, establish a new owner-key set from Setup Mode and re-sign everything; the existing LUKS data remains encrypted independently of Secure Boot.

## Chroot from the Arch ISO

Boot the official Arch ISO with Secure Boot disabled. Identify the partitions:

```bash
lsblk -f
```

Open LUKS and mount the installed layout:

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

Inside the chroot, typical repair commands are:

```bash
pacman -Syu
bootctl --esp-path=/efi install
mkinitcpio -P
sbctl sign-all
sbctl verify
```

Exit and cleanly unmount:

```bash
exit
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Only run `sbctl sign-all` when the expected owner key is present under `/var/lib/sbctl/keys`.

## Restore a root Snapper snapshot

Snapshots do not include the separately mounted home, log, package-cache, or snapshot subvolumes. A root rollback therefore changes operating-system files while retaining user data and logs.

First inspect snapshots from a working boot:

```bash
sudo snapper -c root list
sudo snapper -c root status OLD..NEW
```

For a manual offline rollback, boot the Arch ISO, open LUKS, and mount the Btrfs top level:

```bash
cryptsetup open /dev/nvme0n1p2 cryptroot
mount -o subvolid=5 /dev/mapper/cryptroot /mnt
btrfs subvolume list /mnt
```

Verify the selected snapshot exists at a path similar to:

```text
/mnt/@snapshots/NUMBER/snapshot
```

Then preserve the current root and create a writable snapshot as the new `@`:

```bash
stamp=$(date +%Y%m%d-%H%M%S)
mv /mnt/@ "/mnt/@-broken-$stamp"
btrfs subvolume snapshot /mnt/@snapshots/NUMBER/snapshot /mnt/@
```

The EFI System Partition is separate from Btrfs snapshots. Rebuild the UKIs from the restored root before rebooting so the kernel, initramfs, and modules agree. Remount the restored layout and enter it:

```bash
umount /mnt
mount -o noatime,compress=zstd:1,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o noatime,compress=zstd:1,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd:1,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount /dev/nvme0n1p1 /mnt/efi
arch-chroot /mnt
bootctl --esp-path=/efi update
mkinitcpio -P
sbctl sign-all
sbctl verify
exit
```

Use the actual EFI partition when it is not `/dev/nvme0n1p1`. Only run the `sbctl` commands when the expected owner key is present under `/var/lib/sbctl/keys`; with Secure Boot disabled and no keys available, rebuild the UKIs and recover the signing setup separately.

Then unmount cleanly and reboot:

```bash
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Do not delete the preserved `@-broken-*` subvolume until the restored system and personal data have been checked. A root rollback can leave package-database and separately mounted cache contents at different points; perform a full `pacman -Syu`, rebuild the UKIs, and verify signatures after recovery.

## Reinstall while preserving reproducibility

When recovery is slower or less trustworthy than rebuilding:

1. recover personal data from backups;
2. obtain the repository and its reviewed configuration;
3. perform a fresh installation;
4. run `archctl finish`;
5. restore personal data separately;
6. enroll Secure Boot and TPM again for the new installation.

Do not restore an old TPM token or blindly copy LUKS metadata between installations.
