# Recovery guide

Keep a copy of this guide and the repository somewhere other than the laptop. Recovery commands assume the default disk layout; substitute the actual device from `lsblk`.

## First response checklist

1. Stop and record the exact failure message.
2. Do not clear the TPM, reset Secure Boot keys, reformat, or delete LUKS slots impulsively.
3. Confirm that the LUKS passphrase or offline recovery key is available.
4. Disconnect unneeded external storage before running disk commands.
5. Prefer reversible actions: choose the LTS kernel, use passphrase fallback, or temporarily disable Secure Boot.

## Interrupted OneDrive initial synchronisation

Run these read-only checks as the configured **non-root** user in a graphical
session. Do not post the refresh token, private file names, or full logs publicly.

```bash
systemctl --user show arch-workstation-onedrive-bootstrap.service -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus -p ActiveEnterTimestamp -p InactiveEnterTimestamp -p InvocationID
systemctl --user cat arch-workstation-onedrive-bootstrap.service
journalctl --user -u arch-workstation-onedrive-bootstrap.service -b --no-pager -o short-iso
journalctl --user -u arch-workstation-onedrive-bootstrap.service -b -1 --no-pager -o short-iso
journalctl --user -b --no-pager -o short-iso --since 'YYYY-MM-DD HH:MM:SS' --until 'YYYY-MM-DD HH:MM:SS'
journalctl -b --no-pager -o short-iso --since 'YYYY-MM-DD HH:MM:SS' --until 'YYYY-MM-DD HH:MM:SS' -u systemd-logind.service -u user@$(id -u).service
loginctl show-user "$(id -un)" -p Linger -p State -p Sessions
systemctl --user is-active onedrive.service
ls -ld "$HOME/OneDrive" "$HOME/Documents" "$HOME/Pictures" "$HOME/Videos" "$HOME/.local/share/arch-workstation/folder-backups"
ls -l "$HOME/.local/state/arch-workstation/onedrive/default/" "$HOME/.config/onedrive/config"
```

Replace the timestamps with a short window around the **historical** stop. For
named profiles, inspect their configured sync directories, `onedrive-<name>`
config directories and `onedrive/<name>` state directories instead. Missing paths
or a missing previous-boot journal are not by themselves errors. Compare the
invocation ID and timestamps to distinguish an earlier SIGTERM/stop from the
current `inactive (dead), Result=success` state: a stop request or user-manager
shutdown can yield success without finishing the helper. Check whether logind
ended the last login session (linger disabled), the machine shut down, another
administrator stopped the unit, or the sync client logged an error. The unit has
`TimeoutStartSec=infinity`; a stop after seven minutes is not evidence of a
seven-minute timeout. These logs alone may not identify who requested a stop.

The authoritative completion condition is the profile's `bootstrap-complete`
marker **and** expected home-folder links. A refresh token proves only local
authentication; an inactive unit with no completion marker is not a completed
initial sync. Do not remove the sync database or token, delete a backup, change
the sync directory, or force a resync. Review existing local/remote files and
links before retrying: ordinary OneDrive sync may propagate local changes or
deletions; the folder migration uses `rsync --ignore-existing`, retains the
original directories in dated backups and refuses unexpected links or mounts.
If links or conflicts are unexpected, preserve data and investigate before retrying.

Once the cause is understood, no other bootstrap/monitor is running, the
configuration and backup have been checked, and the graphical login will remain
active for the entire sync, resume the **same one-shot unit** as the configured
user (not as root, not with a profile argument):

```bash
systemctl --user start --no-block arch-workstation-onedrive-bootstrap.service
```

Then follow `journalctl --user -u arch-workstation-onedrive-bootstrap.service -f`
and check `archctl auth onedrive-status` until the completion marker and links
are confirmed. An already running unit should be monitored, not restarted.
If the session must end during a long initial sync, first check `Linger` and
arrange a persistent user manager with your administrator; do not assume that
closing the terminal keeps the user service alive after the last logout. Do not
enable this one-shot unit for automatic starts at every login. A rerun may repeat
initial sync and the safe folder migration, so inspect any partially migrated
folders and backups before starting it again.

## Boot the LTS kernel

systemd-boot normally hides behind a short timeout. Press and hold **Space** during startup to display the menu, then select the `arch-linux-lts.efi` entry.

After booting successfully:

```bash
uname -r
sudo archctl verify
```

Investigate the current kernel or package update before changing the default permanently.

If `archctl update` fails, rerun it after addressing the reported problem: it repeats the official upgrade, boot rebuild/signing, AUR stage, and cache cleanup in order. Boot repair is attempted on an official-upgrade or boot-stage error when signing is configured, but a failed repair is not proof that the UKIs are bootable; do not reboot until signing and UKIs have been checked. An AUR failure after the boot stage does not roll back official packages.

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

mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,var/lib/arch-workstation/pending-credentials,.snapshots}
mount /dev/nvme0n1p1 /mnt/efi
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o subvol=@credentials /dev/mapper/cryptroot /mnt/var/lib/arch-workstation/pending-credentials
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

Snapshots do not include the separately mounted home, log, package-cache, pending-credentials, or snapshot subvolumes. A root rollback therefore changes operating-system files while retaining user data, logs, and staged credentials.

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
mkdir -p /mnt/{efi,home,var/log,var/cache/pacman/pkg,var/lib/arch-workstation/pending-credentials,.snapshots}
mount -o noatime,compress=zstd:1,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd:1,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,subvol=@credentials /dev/mapper/cryptroot /mnt/var/lib/arch-workstation/pending-credentials
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
