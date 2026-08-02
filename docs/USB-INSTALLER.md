# Self-updating installer USB

## Purpose

The USB is both an installer and a recovery medium. It does not depend on GitHub merely to start:

- two complete extracted official Arch live environments are stored as `arch-a` and `arch-b`;
- the current and previous repository snapshots are stored locally with SHA-256 manifests;
- a local T480 profile is stored as the final fallback;
- optional official and AUR package repositories make the whole workstation installable without a network.

Online access improves freshness rather than determining whether the USB works.

## What refreshes, and when

- **Configuration:** a permitted GitHub refresh is resolved to one immutable commit and used in the same boot. The previous accepted repository snapshot remains on the USB.
- **Arch live environment:** only a newer official image is downloaded. It is staged into the non-running slot and becomes current after reboot; the slot that launched the refresh remains the recovery slot.
- **Offline packages:** these are deliberately separate because the cache is large and AUR builds require review. Refresh them from the menu or during USB creation with `--with-offline-packages`.

The stable GRUB loader, `MASON-ARCH/start.sh` and USB layout version are not replaced in place by a GitHub configuration refresh. Rebuild the USB when a future repository release changes the USB layout or bootstrap contract.

## Disk layout

The creation script produces one GPT FAT32 EFI System Partition labelled `MASON_ARCH`:

```text
EFI/BOOT/BOOTX64.EFI          removable GRUB UEFI loader
boot/grub/grub.cfg            current/recovery menu
arch-a/                       complete extracted Arch live slot
arch-b/                       complete extracted Arch live slot
MASON-ARCH/
  start.sh                    stable bootstrap loader
  config/usb.conf             update and GitHub policy
  config/install.conf         emergency local machine profile
  runtime/usb-common.sh       bootstrap support library
  cache/repository/
    current.tar.gz            latest accepted repository snapshot
    current.sha256
    previous.tar.gz           second verified generation, present from creation
    previous.sha256
  cache/pacman/               optional official package repository
  cache/aur/                  optional reviewed AUR package repository
  cache/downloads/            temporary staged downloads
  state/active-slot.cfg       slot selected for the next boot
```

FAT32 is used because UEFI firmware can boot it directly. It is a mutable filesystem, not a secret or tamper-proof store.

## Online-first boot sequence

1. GRUB boots the slot named in `active-slot.cfg`.
2. Archiso runs `MASON-ARCH/start.sh` automatically.
3. The loader locates and remounts the USB read-write.
4. It checks connectivity and can open `iwctl`.
5. When `REPO_URL` is configured, it resolves the configured Git ref through GitHub's public API and downloads the resulting immutable commit archive.
6. Required files and all Bash scripts are checked before a snapshot is accepted.
7. The old valid `current` repository becomes `previous`; the downloaded snapshot becomes `current` only after checksum verification.
8. The exact accepted commit is retained as source provenance for the installed repository copy.
9. The configured profile is copied into the temporary live repository and the menu starts.
10. According to `ARCH_UPDATE_POLICY`, the menu checks the official current Arch image.
11. A new ISO is downloaded and checked with both the published SHA-256 value and the Arch ISO PGP signature.
12. The image is extracted into the **non-running** slot and structurally verified.
13. Only then is that slot selected for the next boot. The current running slot remains the recovery copy.

A freshly downloaded Arch environment therefore takes effect after one reboot. The GitHub configuration takes effect in the current boot.

## Update generations

Updates intentionally do not destroy the only fallback:

- **Arch:** the running slot is immutable for that session. Refresh writes the other slot, verifies it and changes the next-boot selector. The old running slot remains selectable as **recovery slot**.
- **Repository:** the accepted current snapshot rotates to previous before a new current snapshot is committed. Startup automatically falls back to previous when current fails checksum or structure validation.
- **Packages:** new official and AUR repositories are built in `.new` directories. The pair is activated only after complete manifests have been written and verified; failed activation restores the old pair.

Startup also repairs recognised interrupted states: it restores a complete `.old` Arch or package-cache generation, completes a lone verified `.new` Arch slot, and changes the active slot when the selected slot is invalid but the other one is complete.

The system keeps one recovery generation rather than accumulating unlimited old images.

## Configure GitHub

Copy the ignored local policy file:

```bash
cp config/usb.conf.example config/usb.conf
```

Recommended moving-branch configuration:

```bash
REPO_URL="https://github.com/YOUR-NAME/arch-t480-workstation"
REPO_REF="main"
REPO_PINNED_COMMIT=""
INSTALL_CONFIG_SOURCE="repository"
INSTALL_CONFIG_REPO_PATH="profiles/t480.conf"
```

Only public HTTPS GitHub repositories are accepted. Never put a personal access token in `usb.conf` because the USB partition is readable as ordinary FAT storage.

For a higher-control release process, pin a reviewed full commit hash:

```bash
REPO_PINNED_COMMIT="0123456789abcdef0123456789abcdef01234567"
```

A pin prevents a moving branch from changing what root executes until the hash is deliberately updated.

## Update policies

Each policy is `always`, `prompt` or `never`:

```bash
REPO_UPDATE_POLICY="always"
ARCH_UPDATE_POLICY="always"
PACKAGE_CACHE_UPDATE_POLICY="prompt"
AUR_CACHE_UPDATE_POLICY="prompt"
```

The defaults automatically attempt the small Git repository refresh and the official Arch image check. Package caches are prompted because they are large and AUR refreshes require build-file review.

`KEEP_DOWNLOADED_ISO=false` removes the ISO after extraction. The two extracted slots are the bootable backup; retaining the ISO is not necessary for normal recovery.

## Create the USB

Review the target by stable identifier:

```bash
ls -l /dev/disk/by-id/usb-*
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN,RM
```

Then run:

```bash
sudo ./usb/create-usb.sh \
  --disk /dev/disk/by-id/usb-YOUR_DEVICE \
  --usb-config config/usb.conf \
  --install-config profiles/t480.conf \
  --repo-url https://github.com/YOUR-NAME/arch-t480-workstation \
  --repo-ref main
```

The script refuses a non-removable disk unless `--allow-non-removable` is explicitly supplied, refuses the running root disk, checks active swap and requires the exact target-specific erase phrase. It seeds both repository generations with the local source snapshot, so repository fallback exists before the first online refresh.

A basic USB needs at least 8 GiB. A 64 GiB or larger device is recommended when keeping full package caches and enough free space to stage their replacement.

### Host tools

The basic creator requires:

- a working x86-64 UEFI GRUB installation (`grub-install` with `x86_64-efi` modules);
- `mkfs.fat`, `sgdisk`, `bsdtar`, `curl`, `sha256sum`;
- standard Linux block, mount and archive utilities.

An Arch host additionally performs PGP verification during creation. On a non-Arch host, creation verifies the ISO against the HTTPS SHA-256 list; the first live refresh uses the Arch keyring for both PGP and SHA-256 verification.

Ubuntu or Debian:

```bash
sudo apt update
sudo apt install grub-efi-amd64-bin dosfstools gdisk libarchive-tools parted curl util-linux
```

Arch:

```bash
sudo pacman -S --needed grub dosfstools gptfdisk libarchive curl
```

## Complete offline package cache

Run creation from Arch with:

```bash
sudo ./usb/create-usb.sh \
  --disk /dev/disk/by-id/usb-YOUR_DEVICE \
  --usb-config config/usb.conf \
  --repo-url https://github.com/YOUR-NAME/arch-t480-workstation \
  --with-offline-packages
```

Alternatively boot the USB, choose **Refresh the complete offline package cache**, and review each AUR PKGBUILD and `.SRCINFO` before typing its exact build confirmation.

The official cache includes every package generated by `scripts/lib/packages.sh` plus dependency packages introduced by the reviewed AUR builds. `install.sh` validates that every requested package resolves before touching the target disk.

Before a refreshed cache replaces the previous generation, the builder loads the staged repository databases with an empty pacman database and proves that every configured package and dependency resolves from those staged files alone. The activated generation is flushed before the rollback directories are removed.

After changing `EXTRA_OFFICIAL_PACKAGES`, `AUR_PACKAGES`, hardware, gaming or other package-affecting switches, refresh the cache before relying on offline installation.

## Installer choices

**Online first, verified USB fallback** uses current Arch repositories when the network check succeeds. If not, it validates and uses the USB package repositories.

**Force fully offline cache** refuses to contact package mirrors and fails before disk erasure when the cache is missing, damaged or incomplete.

Both paths use the same reviewed profile and retain the same destructive disk confirmation.

## Manual maintenance from the live shell

Locate the USB automatically or pass its mount root:

```bash
sudo ./usb/verify-usb.sh
sudo ./usb/refresh-arch.sh --if-newer
sudo ./usb/refresh-packages.sh \
  --usb-root /run/archiso/bootmnt \
  --install-config /run/mason-installer/repo/config/install.conf
```

Exit status `10` from `refresh-arch.sh` means a verified new slot was selected and a reboot is required to run it.

## Read-only fallback

The loader tests whether the USB can actually be written after attempting a read-write remount. When write access is unavailable, it does not attempt repository, Arch or package-cache replacement. It still boots either cached Arch slot, verifies/loads the cached repository generations and can install from a complete existing offline package cache.

This makes a write-protected or firmware-mounted-read-only USB useful for recovery, but its content cannot become fresher until it is writable again.

## Recovery behaviour

- Choose **recovery slot** in GRUB when the newly selected live image does not boot.
- Choose **maintenance shell** to boot Arch without launching the automated installer.
- When GitHub is unavailable, the current local snapshot is used.
- When the current repository checksum fails, the previous snapshot is used.
- When both repository copies are damaged, rebuild the USB from a known-good clone rather than bypassing verification.

The USB should still be backed up or reproducible from Git. Its checksums detect accidental damage but do not stop someone with physical write access from replacing both a file and its checksum.
