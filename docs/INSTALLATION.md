# Installation guide

This guide installs a complete Arch workstation onto one whole x86-64 disk. The target partition table and all target data are deleted.

The preferred path is the repository's self-updating USB. A manual official-ISO path remains available for recovery or development.

## 1. Prepare safely

- Back up personal files and open the backup from another machine.
- Keep the LUKS passphrase and later recovery key outside the laptop.
- Update T480 firmware, including Thunderbolt firmware, before replacing the existing system.
- Connect AC power.
- Test the first release on a spare SSD where practical.
- Read [SECURITY.md](SECURITY.md), especially the GitHub and mutable-USB trust boundaries.

Confirm the intended target disk and USB by model and serial rather than relying only on names such as `/dev/nvme0n1` or `/dev/sdb`.

## 2. Create the installer USB

Follow [USB-INSTALLER.md](USB-INSTALLER.md). The normal command is:

```bash
cp config/usb.conf.example config/usb.conf
vim config/usb.conf
vim profiles/t480.conf

sudo ./usb/create-usb.sh \
  --disk /dev/disk/by-id/usb-YOUR_DEVICE \
  --usb-config config/usb.conf \
  --repo-url https://github.com/YOUR-NAME/arch-t480-workstation
```

Add `--with-offline-packages` from an Arch host when the USB must install the complete workstation without Internet access.

The creation command erases the selected USB only after displaying its details and receiving the exact phrase `ERASE /dev/...`.

## 3. Firmware state for installation

On a T480, press **F1** during startup. Firmware wording varies, but the intended state is:

| Setting | Installation value |
|---|---|
| UEFI/Legacy Boot | UEFI only |
| CSM/Legacy support | Disabled |
| Security Chip / TPM | Enabled and active |
| Secure Boot | Disabled while using the installer USB |
| Secure Boot key state | Setup Mode will be required later for owner-key enrollment |

Do not restore factory Secure Boot keys after the repository enrolls owner keys. The default retains Microsoft UEFI certificates alongside the owner key for option-ROM and firmware compatibility.

## 4. Boot the current USB slot

Choose:

```text
Mason Arch installer - current cached slot
```

The recovery entry boots the other complete Arch slot. The maintenance entry boots the live system without running the installer menu.

At startup the loader:

1. checks the network and optionally opens `iwctl`;
2. resolves the configured GitHub ref and downloads its immutable commit archive when permitted;
3. validates it and rotates the previous local repository generation;
4. uses the selected repository profile immediately;
5. checks for a fresher official Arch image;
6. downloads, PGP/SHA-256 verifies and extracts it to the non-running slot;
7. offers a reboot so installation can continue from that fresh slot.

A failed update does not delete the currently running Arch environment or the previous repository snapshot.

## 5. Review the machine profile

The default profile is `profiles/t480.conf`. It expects:

```bash
DISK="/dev/nvme0n1"
HOSTNAME="arch-t480"
USERNAME="mason"
CPU_VENDOR="intel"
GPU_VENDOR="intel"
ENABLE_T480=true
```

Before installation, use the maintenance shell or menu shell to check:

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS
```

A T480 variant with discrete or hybrid NVIDIA graphics is outside this profile. Do not treat `GPU_VENDOR="intel"` as correct without checking the hardware.

The profile is sourced by Bash and is executable policy. Review Git changes before allowing a remote branch to run as root.

## 6. Choose the package source

### Online first, USB fallback

This is the normal option. It uses current Arch repositories when reachable. If connectivity is absent, the installer validates and uses the complete local official and AUR caches.

### Force fully offline

This option makes no package-mirror attempt. Before any disk modification, it verifies manifests, loads the local repository databases and checks that every configured package resolves.

A basic USB without package caches can still boot and load its local configuration, but it cannot perform a full offline installation.

## 7. Run the destructive installation

The installer runs preflight before the erase prompt. It checks:

- x86-64 and UEFI mode;
- Archiso context;
- target whole-disk type and mounted descendants;
- active target swap;
- CPU/DMI profile mismatches;
- TPM visibility;
- Secure Boot state;
- online source availability or complete offline-cache resolution.

It displays the selected disk and requires the exact target-specific phrase, for example:

```text
ERASE /dev/nvme0n1
```

The LUKS passphrase and user password are collected before the disk is changed.

The target receives:

- a 1 GiB FAT32 EFI System Partition at `/efi`;
- LUKS2 containing Btrfs;
- separate root, home, log, package-cache and snapshot subvolumes;
- `linux` and `linux-lts` UKIs;
- systemd-boot;
- the complete configured official package set;
- configured AUR application packages as part of an offline install;
- a root-owned source snapshot at `/opt/arch-workstation`.

When the command completes, reboot and remove or deprioritise the installer USB.

## 8. First boot and provisioning

Unlock LUKS with the passphrase and log in as the configured user. Then run:

```bash
archctl provision
```

The command applies Ansible roles, services, dotfiles, VS Code settings and the PowerShell profile. When Internet is available it first performs a full Arch update and installs/reviews any AUR applications not already supplied by an offline installation. Without Internet, it uses the already installed complete package set and skips network-only extension/module downloads.

Log out and back in after provisioning when Docker group membership is enabled.

The installed policy file is:

```text
/etc/arch-installer/install.conf
```

It is owned by `root:wheel`, mode `0640`. `/opt/arch-workstation/config/install.conf` points to it. One-shot secret paths, erase confirmation, unattended mode, USB cache paths and Secure Boot confirmation are cleared in the installed copy.

## 9. Secure Boot

Firmware must be in **Setup Mode**, with Secure Boot enforcement still disabled. Boot Arch and run:

```bash
sudo archctl secure-boot
```

The command creates owner keys, requires the exact enrollment phrase, enrolls them with `sbctl`, includes Microsoft certificates by default, updates systemd-boot, rebuilds both UKIs and signs/records EFI assets.

Reboot into firmware and enable Secure Boot **without restoring factory keys**. Then verify:

```bash
sudo sbctl status
sudo sbctl verify
bootctl status
```

Do not enroll TPM unlocking until the signed system boots with Secure Boot active.

## 10. Recovery key and TPM2

Create an additional high-entropy LUKS recovery credential:

```bash
sudo archctl recovery-key
```

Store it offline and separately. The original passphrase remains valid.

Then enroll TPM2 unlocking:

```bash
sudo archctl tpm-enroll
```

The default binds to PCR 7 and requires a TPM PIN. Existing systemd TPM tokens are replaced while ordinary passphrase slots remain.

Reboot and test both TPM/PIN and passphrase paths, then run:

```bash
sudo archctl verify
```

## 11. Manual official-ISO fallback

When the custom USB cannot be used, boot the official Arch ISO in UEFI mode with Secure Boot disabled, connect the network and obtain the repository:

```bash
pacman -Sy --needed git
git clone https://github.com/YOUR-NAME/arch-t480-workstation
cd arch-t480-workstation
cp profiles/t480.conf config/install.conf
sudo ./install.sh --config config/install.conf --preflight-only
sudo ./install.sh --config config/install.conf
```

This path uses current online repositories unless a valid offline repository path is deliberately configured.

## 12. Non-interactive target installation

The target installer supports strict non-interactive mode, but the USB creator, Secure Boot enrollment and AUR review retain explicit safety gates. Non-interactive target installation requires:

```bash
NONINTERACTIVE=true
LUKS_PASSPHRASE_FILE="/root/arch-secrets/luks-passphrase"
USER_PASSWORD_FILE="/root/arch-secrets/user-password"
WIPE_CONFIRMATION="ERASE /dev/nvme0n1"
```

Secret files must be root-readable with mode `0400` or `0600`; only their first line is used. Do not commit them or place them on the FAT USB partition.
