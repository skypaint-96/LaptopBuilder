# Arch T480 workstation

A reproducible vanilla Arch Linux workstation for a ThinkPad T480, with a self-updating, self-contained installer USB.

The normal experience is:

```text
Boot USB
  -> try GitHub for the newest reviewed configuration
  -> keep using the verified USB copy if GitHub is unavailable
  -> check the current official Arch image
  -> stage a newer image in the non-running USB slot
  -> install online, or from the complete USB package cache
```

The USB always retains two extracted Arch live environments and two repository generations. An update is written and verified before it becomes current; the running Arch slot is never overwritten.

If the USB cannot be remounted read-write, refreshes are skipped and the existing verified Arch, repository and package-cache copies remain usable. A GitHub refresh records the exact accepted commit in the installed source snapshot.

> **Destructive software:** both `usb/create-usb.sh` and `install.sh` erase an entire selected disk. They display the model and serial and require an exact `ERASE /dev/...` confirmation. Verify backups and disk identity first.

## What the workstation contains

- Vanilla x86-64 Arch Linux in UEFI mode.
- Xfce on X11 for broad support and low idle resource use.
- LUKS2, Btrfs subvolumes, zram, Snapper, `linux` and `linux-lts`.
- systemd-boot Unified Kernel Images.
- Owner-controlled Secure Boot with `sbctl`, followed by TPM2/PCR 7 enrollment with a PIN and retained LUKS passphrase.
- NetworkManager, PipeWire, Bluetooth and T480 power/firmware tooling.
- Edge, Vim, PowerShell, .NET, Visual Studio Code, Docker, Git and Steam.
- Bash for the live installer, Ansible for repeatable machine configuration and PowerShell for the user profile.

## Create the installer USB

Clone or extract this repository on an existing Linux system. Creating the basic USB needs GRUB's x86-64 EFI files, `dosfstools`, `sgdisk`, `bsdtar`, `curl` and common block-device tools. Building the full offline package cache is easiest from Arch Linux or the official Arch live environment because it requires `pacman` and builds the reviewed AUR packages.

On Ubuntu or Debian, install the creator prerequisites with:

```bash
sudo apt install grub-efi-amd64-bin dosfstools gdisk libarchive-tools parted curl util-linux
```

On Arch:

```bash
sudo pacman -S --needed grub dosfstools gptfdisk libarchive curl
```

Create local USB policy:

```bash
cp config/usb.conf.example config/usb.conf
vim config/usb.conf
```

Set your public GitHub repository, for example:

```bash
REPO_URL="https://github.com/YOUR-NAME/arch-t480-workstation"
REPO_REF="main"
```

Review the version-controlled machine profile:

```bash
vim profiles/t480.conf
```

Identify the USB by model and serial, preferably through `/dev/disk/by-id`:

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN,RM
```

Create a bootable USB with the cached Arch live system and repository:

```bash
sudo ./usb/create-usb.sh \
  --disk /dev/disk/by-id/usb-YOUR_USB_DEVICE \
  --usb-config config/usb.conf \
  --repo-url https://github.com/YOUR-NAME/arch-t480-workstation
```

For a **complete offline installation**, use an Arch host and a 64 GB or larger USB, then add:

```bash
  --with-offline-packages
```

That downloads the dependency-complete official package set and interactively builds the configured AUR packages into local pacman repositories. A basic USB remains fully capable of booting and loading the cached configuration offline, but installation packages still need the network until the package cache has been built.

See [USB-INSTALLER.md](docs/USB-INSTALLER.md) for host prerequisites, update policies, A/B recovery and cache maintenance.

## Install from the USB

1. Back up the T480 and connect AC power.
2. In firmware, use UEFI-only boot, enable the TPM and temporarily disable Secure Boot.
3. Boot **Mason Arch installer - current cached slot**.
4. Connect Wi-Fi when prompted.
5. The loader resolves the configured GitHub ref to an immutable commit, downloads that commit archive, validates it and makes it `current`; the previous snapshot remains available.
6. When a newer official Arch live image exists, it is downloaded, PGP/SHA-256 verified and staged in the other slot. Reboot when offered to run that fresh image.
7. Choose the online-first or force-offline installation option.
8. Verify the displayed target disk and enter the exact erase confirmation.

After the first boot:

```bash
archctl provision
sudo archctl secure-boot
```

Enable Secure Boot in firmware without restoring factory keys, boot the signed system, then:

```bash
sudo archctl recovery-key
sudo archctl tpm-enroll
sudo archctl verify
```

The detailed procedure and safety checks are in [INSTALLATION.md](docs/INSTALLATION.md).

## Keeping configuration in GitHub

`profiles/t480.conf` is the normal source of machine policy. Edit it, commit and push. The next USB boot fetches that branch and uses the new profile immediately. If the network, GitHub or validation fails, the USB uses its last checksum-verified snapshot; if that is damaged, it uses the previous snapshot.

Common package changes require only profile edits:

```bash
EXTRA_OFFICIAL_PACKAGES="audacity keepassxc"
AUR_PACKAGES="microsoft-edge-stable-bin visual-studio-code-bin powershell-bin another-reviewed-package"
```

Refresh the USB package cache after changing package selections if offline installation matters.

## Repository guide

- [USB installer and cache lifecycle](docs/USB-INSTALLER.md)
- [End-to-end installation](docs/INSTALLATION.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Customising profiles and software](docs/CUSTOMISING.md)
- [Package sources and offline caches](docs/PACKAGES.md)
- [Security and trust boundaries](docs/SECURITY.md)
- [Recovery](docs/RECOVERY.md)
- [Testing](docs/TESTING.md)
- [T480 notes](docs/T480.md)

## Validation status

`make test` performs Bash, YAML, JSON, link, configuration, source-copy, USB fallback and safety tests. CI additionally runs ShellCheck, Ansible syntax, PowerShell parsing, current Arch package resolution and AUR metadata checks.

The repository has not been exercised against your physical T480 firmware, TPM and target SSD. Test the first release on a spare SSD and retain a separate, verified personal-data backup.
