# Custom installation USB

Version 0.3 restores the USB builder as a supported part of the project. The USB is intentionally split into two layers:

1. an immutable custom ArchISO that contains the launcher and an embedded fallback copy of the repository;
2. a writable ext4 partition labelled `ARCHWS_DATA` that holds policy, encrypted credentials, caches, logs, and refresh state.

This design does not depend on the old `bootmnt`/`mason-arch` mount path. At startup the launcher waits for udev and retries discovery of the appended partition before reporting a mount failure. If the writable partition still cannot be mounted, it reports the problem and can use the embedded project with live network sources.

## Requirements

Build the USB from an installed Arch Linux system. The builder installs missing Arch packages such as `archiso`, `gptfdisk`, `e2fsprogs`, `jq`, and GnuPG through `pacman`.

Use at least an 8 GiB USB. A 16 GiB or larger device is recommended because the full layout can contain:

- the bootable custom ISO;
- a copy of that custom ISO;
- the current official Arch ISO and checksum/signature metadata;
- the configured official package set and its dependency closure;
- package repository databases;
- a Git mirror and bundle of this project.

## Basic build

Clone the repository on Arch:

```bash
git clone <credential-free-repository-url> arch-workstation
cd arch-workstation
```

Then run:

```bash
./build-usb.sh --device /dev/sdX --configure
```

Replace `/dev/sdX` with the whole USB disk, never a partition and never the internal NVMe disk. The builder displays model, serial number, transport, and size, then requires the exact confirmation:

```text
WRITE /dev/sdX
```

The guided configuration sets the installation disk, hostname, username, locale, keymap, CPU/GPU profile, T480 role, Secure Boot policy, and TPM policy before the lengthy ISO build starts. Repeatable non-interactive overrides are also available:

```bash
./build-usb.sh --device /dev/sdX --no-configure \
  --set DISK=/dev/nvme0n1 \
  --set HOSTNAME=arch-t480 \
  --set USERNAME=mason
```

The builder derives the live Git URL from `origin` when possible. A public credential-free HTTPS URL is the most reliable choice in the live environment. The selected branch/tag/commit defaults to the current branch or `main`.

## Build with encrypted credentials

Copy the example outside version control or to the ignored local path:

```bash
cp config/usb-secrets.json.example config/usb-secrets.json
chmod 0600 config/usb-secrets.json
vim config/usb-secrets.json
```

The supported fields are:

```json
{
  "username": "archuser",
  "user_password": null,
  "luks_passphrase": null,
  "tpm2_pin": null,
  "media_unlock_passphrase": null
}
```

`null` or absent fields are prompted together at the beginning of the build. Supply the file with:

```bash
./build-usb.sh \
  --device /dev/sdX \
  --configure \
  --secure-file config/usb-secrets.json
```

The plaintext JSON must be a non-symlink regular file with mode `0400` or `0600`. It is never copied to the ISO or USB. The builder creates a GnuPG AES-256 symmetric ciphertext and verifies it by decrypting it in a RAM-backed temporary directory before copying only the ciphertext to `ARCHWS_DATA`.

The bundle unlock passphrase is not stored on the USB and must be at least 12 characters. At live boot it is entered once, after which the credentials are materialised under `/run/arch-workstation/secrets` with mode `0600` and used by the installer. Anyone who copies the ciphertext can attempt offline passphrase guesses, so use a genuinely strong bundle passphrase rather than the short daily TPM PIN.

When an encrypted bundle is included, the persistent and embedded installation configurations use a placeholder username. The real username remains inside the encrypted bundle and replaces the placeholder only in the RAM-backed runtime configuration. The live configuration editor also restores that placeholder while a bundle exists, so replace the encrypted bundle when changing the installation username.

Delete the plaintext source file after the build when it is no longer needed. Deletion on an SSD cannot guarantee that every historical flash cell is immediately erased, so avoid creating the plaintext file on unencrypted storage.

## USB build stages

The builder:

1. validates the local project and installation configuration;
2. collects all requested credentials before the long-running work starts;
3. copies ArchISO's current `releng` profile;
4. embeds the tracked project files, fallback configuration, and `archws` launcher;
5. adds an automatic tty1 launcher to the live root login;
6. builds the custom ISO with `mkarchiso`;
7. writes and byte-compares the ISO-sized region of the selected USB;
8. removes stale signatures, extends the hybrid ISO GPT into the remaining space, and creates the `ARCHWS_DATA` ext4 partition;
9. stores configuration and optional encrypted credentials;
10. refreshes the live Git cache, current official Arch ISO backup, repository databases, and official package cache;
11. unmounts, checks the ext4 filesystem, then reads back and verifies the project bundle, custom-ISO checksum, metadata, and encrypted-bundle checksum.

The builder does not store Git URLs containing inline credentials.
Repository metadata is parsed as an allow-listed base64 scalar format rather than sourced as shell code. Live repository URLs are restricted to credential-free HTTPS or supported SSH forms, and the selected Git ref is validated before it is passed to Git.

The launcher and project declare a small USB API version. A live branch that is too old or otherwise incompatible is rejected automatically, after which the launcher tries the persistent bundle and embedded snapshot instead. This prevents an outdated remote branch from silently replacing a newer working USB toolchain.

## Boot menu

Boot the USB with Secure Boot disabled. The launcher starts automatically on tty1 and offers:

```text
1) Install using live project and live Arch sources
2) Install using the offline project and official package cache
3) Refresh all offline caches without installing
4) Configure installation settings
5) Create or replace the encrypted installation-secret bundle
6) Configure or check networking
7) Run media and hardware diagnostics
8) Open a shell
9) Exit this launcher
```

Run `archws` from the root shell to reopen it.

### Live installation

This is the default. It:

- checks internet access first and offers the live ISO's `iwctl` interface when Wi-Fi is not connected;
- fetches `ARCHWS_REPO_URL` and checks out `ARCHWS_REPO_REF` in RAM;
- falls back to the persistent Git bundle and then the embedded copy if needed;
- refreshes the project mirror/bundle;
- downloads and verifies the current official Arch ISO into the offline cache when it changed;
- refreshes `core`, `extra`, and `multilib` databases;
- downloads the complete configured official package set and dependencies;
- bind-mounts the persistent package cache over the live ISO package cache;
- runs the normal preflight and installer.

No target-disk change occurs until the cache refresh, credential collection, firmware checks, package resolution, and exact erase confirmation have completed.

### Offline installation

Offline mode restores the cached pacman databases and package cache, clones the cached Git bundle, and resolves the complete transaction without a network check. The base system is bootstrapped with `pacstrap -U` from the verified local package-file list, avoiding pacstrap's normal `-Sy` repository synchronisation. The package cache and sync databases are then copied into the encrypted target so official-package provisioning can reuse them after first boot.

The offline guarantee covers the project and official Arch packages represented by the configured package manifest. AUR packages such as Edge, VS Code, and PowerShell are intentionally completed by first-boot provisioning once a network connection is available. AUR build instructions and their upstream binary payloads are not treated as an official Arch cache.

## Refresh without installing

From the USB menu, choose option 3. This changes only `ARCHWS_DATA`.

From an installed Arch system, insert the existing USB and run:

```bash
./build-usb.sh --refresh-only --device /dev/sdX
```

By default this preserves the persistent installation configuration and encrypted credential bundle, while updating the project cache, official ISO backup, package databases, and package files. Changes are explicit:

```bash
# Replace or edit saved configuration while refreshing.
./build-usb.sh --refresh-only --device /dev/sdX --configure
./build-usb.sh --refresh-only --device /dev/sdX --set HOSTNAME=arch-t480

# Replace the encrypted bundle, prompting for every missing field.
./build-usb.sh --refresh-only --device /dev/sdX \
  --secure-file config/usb-secrets.json

# Deliberately remove the encrypted bundle. Because encrypted builds hide the
# real username in plaintext config, supply/configure it at the same time.
./build-usb.sh --refresh-only --device /dev/sdX \
  --no-secrets --set USERNAME=mason
```

`--refresh-only` cannot be combined with `--no-refresh-cache`. A v0.1/v0.2 USB using the old `mason-arch`/`bootmnt` layout must be erased and rebuilt once; cache-only refresh is supported after the first v0.3 build.

When an existing encrypted bundle is removed, the builder refuses to leave the deliberately generic `archuser` placeholder as the installation account. Use `--configure` or `--set USERNAME=...` in the same refresh command.

To replace the immutable boot environment itself with a newly built ArchISO and current embedded project, run a normal USB build again. A running live system never rewrites the boot image it is currently executing.

## ISO-only build

```bash
./build-usb.sh --iso-only --no-configure --no-secrets
```

An ISO-only build has no writable `ARCHWS_DATA` partition, so `--include-secrets` and `--secure-file` are deliberately rejected. Build or refresh a complete USB when encrypted credentials need to be stored persistently.

The ISO and SHA-256 file are written below `usb/output/`. No block device is modified.

## Persistent layout

```text
ARCHWS_DATA/
└── arch-workstation/
    ├── media.env
    ├── config/
    │   └── install.conf
    ├── secure/
    │   ├── install-secrets.gpg
    │   └── install-secrets.gpg.meta
    ├── cache/
    │   ├── repo/
    │   │   ├── mirror.git/
    │   │   ├── project.bundle
    │   │   └── repository.env
    │   ├── archiso/
    │   │   ├── current.env
    │   │   ├── archlinux-...-x86_64.iso
    │   │   └── custom/
    │   └── pacman/
    │       ├── db/sync/
    │       ├── pkg/
    │       └── package-manifest.txt
    ├── logs/
    └── state/
```

## Diagnostics and I/O errors

Option 6 displays:

- UEFI, Secure Boot Setup Mode, and TPM state;
- whether `ARCHWS_DATA` mounted successfully;
- internet and repository settings;
- cache metadata and free space;
- full block-device identity;
- recent kernel messages matching USB reset, medium, buffer, or I/O errors.

A missing writable partition is handled as a cache/configuration failure rather than as a failed live-ISO boot. Genuine kernel `I/O error`, USB reset, or medium-error messages still indicate an unreliable write, device, cable, or port and should not be ignored.
