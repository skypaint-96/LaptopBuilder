# Arch T480 Workstation

A reproducible vanilla Arch Linux workstation build for x86-64 UEFI hardware, with a Lenovo ThinkPad T480 profile enabled by default.

The repository deliberately treats the operating system as rebuildable configuration. It installs a compact Xfce/X11 base, provisions the requested applications, creates an owner-controlled Secure Boot chain, and enrols TPM2-backed LUKS unlocking while retaining a normal recovery passphrase.

> **Destructive:** the installer owns and erases the entire configured disk. Back up the machine and run the non-destructive preflight first.

## What version 0.2 automates

Version 0.2 incorporates the failures and manual repairs found during the first physical T480 installation:

- enables and synchronises `multilib` in the live ISO before package resolution or `pacstrap`;
- resolves every configured official package and AUR package name before disk erasure;
- requires Secure Boot Setup Mode before installation, then enrols keys and signs every EFI binary during installation;
- installs prebuilt `paru-bin`, avoiding a Rust/Cargo provider choice and a lengthy Paru source build;
- uses one sudo authentication for the complete provisioning run;
- invokes Ansible through that authenticated root session rather than failing at `become`;
- uses an explicit AUR allow-list with optional non-interactive review suppression;
- provides a resumable `archctl finish` state machine;
- detects and signs all `.efi` files below `/efi/EFI`, including the fallback loader, systemd-boot, and both UKIs;
- re-signs and verifies the complete boot chain after provisioning and future updates;
- provides `start.sh` compatibility and an `upgrade-existing.sh` migration tool.

The firmware still has two unavoidable physical trust-boundary actions: clear keys to enter Setup Mode before installation, and enable Secure Boot after the installer enrols the replacement keys.

## Baseline

- Vanilla Arch Linux, x86-64, UEFI/GPT only.
- Xfce on X11 for low idle resource use and mature application support.
- `linux` and `linux-lts` Unified Kernel Images (UKIs).
- LUKS2 encrypted root on Btrfs with zstd compression.
- Separate Btrfs subvolumes for root, home, logs, package cache, and snapshots.
- systemd-boot with a standard fallback loader.
- Secure Boot owner keys managed by `sbctl`, retaining Microsoft certificates by default for compatibility.
- TPM2 unlock using `systemd-cryptenroll`, PCR 7, and a daily PIN by default.
- NetworkManager, PipeWire, LightDM, zram, Snapper, TLP, thermald, fwupd, and SMART monitoring.
- Bash bootstrap, root-run Ansible provisioning, and user-run PowerShell/VS Code configuration.

## Requested applications

| Requirement | Package source |
|---|---|
| Microsoft Edge | `microsoft-edge-stable-bin` from AUR |
| Vim | `vim` from official repositories |
| PowerShell | `powershell-bin` from AUR |
| .NET | `dotnet-sdk` from official repositories |
| Visual Studio Code | `visual-studio-code-bin` from AUR |
| Docker | `docker`, `docker-buildx`, `docker-compose` |
| Git | `git` |
| Steam | `steam`, GameMode, MangoHud, and explicit Intel/AMD 32-bit Vulkan userspace |

The default AUR bootstrap is `paru-bin`. Automated AUR mode skips routine review prompts but only acts on the package names explicitly listed in `AUR_PACKAGES`. Set `AUR_NONINTERACTIVE=false` to restore manual PKGBUILD review.

## Fresh installation

### 1. Prepare firmware

On the T480, press **F1** during startup and configure:

1. UEFI-only booting; disable Legacy/CSM.
2. TPM/Security Chip enabled.
3. Secure Boot disabled.
4. Clear/reset the Secure Boot keys so firmware reports **Setup Mode enabled**.
5. Do not restore factory keys.

Boot the official Arch ISO in UEFI mode and connect it to the network.

### 2. Configure and preflight

```bash
pacman -Sy --needed git

git clone <repository-url> arch-t480-workstation
cd arch-t480-workstation
cp config/install.conf.example config/install.conf
vim config/install.conf

./start.sh preflight
```

The preflight checks firmware state, TPM visibility, target-disk safety, network access, `multilib`, all official package names, and the AUR allow-list. It makes no disk changes.

### 3. Install

```bash
./start.sh --reboot-firmware
```

The wrapper obtains root privilege, asks for the LUKS passphrase and Linux user password, requires the exact erase phrase, installs Arch, enrols the Secure Boot owner keys, creates both UKIs, and signs/registers every EFI executable.

### 4. Enable Secure Boot and finish

After installation:

1. Reboot into firmware setup.
2. Enable Secure Boot without clearing or restoring keys.
3. Remove the USB and boot Arch.
4. Enter the retained LUKS passphrase once and log in.
5. Run:

```bash
archctl finish
```

`finish` is safe to rerun. Run it normally; an accidental `sudo archctl finish` is automatically dropped back to the invoking user. It detects the current stage, opens one sudo session, provisions the machine, installs the AUR allow-list, re-verifies the signed boot chain, enrols TPM2 unlock, and runs the strict final audit. TPM enrolment still asks for the retained LUKS credential and the new daily PIN because those secrets should not be stored in the repository.

On the next reboot, normal startup should ask for the TPM PIN rather than the long LUKS passphrase. Keep the long passphrase as the recovery route.

## Existing 0.1 installation

Extract the 0.2 release somewhere outside `/opt/arch-workstation`, then run:

```bash
./upgrade-existing.sh
archctl finish
```

The upgrader creates a root-only backup in `/var/backups/arch-workstation`, preserves `/etc/arch-installer/install.conf`, replaces the installed automation atomically, and enables the reduced-prompt defaults. See [docs/MIGRATION.md](docs/MIGRATION.md).

## Commands

```text
archctl finish              Resume the complete first-boot workflow
archctl status              Show the detected setup stage and next action
archctl provision           Reapply system and user configuration
archctl secure-boot         Enrol/sign or repair the Secure Boot chain
archctl tpm-enroll          Enrol TPM2 unlocking after Secure Boot is active
archctl tpm-remove          Return to passphrase-only unlocking
archctl recovery-key        Add and print a separate LUKS recovery key
archctl verify              Run the strict installation/security audit
archctl snapshot TEXT       Create a manual Snapper root snapshot
archctl update              Update packages, rebuild UKIs, sign, and verify
```

Running `/opt/arch-workstation/start.sh` or `arch-workstation-start` on an installed system is equivalent to `archctl finish` when no command is supplied.

## Repository layout

```text
.
├── install.sh                 destructive live-ISO installer
├── start.sh                   context-aware compatibility entry point
├── upgrade-existing.sh        safe migration of an installed automation copy
├── archctl                    installed-system command dispatcher
├── config/                    user-editable policy
├── scripts/install/           preflight, disk, base, and chroot stages
├── scripts/security/          state, signing, TPM, recovery, and verification
├── ansible/                   idempotent workstation roles
├── powershell/                PowerShell profile/module configuration
├── dotfiles/                  Git and Vim defaults
├── vscode/                    settings and extension allow-list
├── docs/                      operations, security, recovery, and design
└── tests/                     static, structural, and package checks
```

## Important limits

- Whole-disk installation only; no dual boot or partition preservation.
- No hibernation; zram is used instead.
- Snapshots are not backups.
- Docker-group membership is effectively root-equivalent.
- AUR packages execute community-maintained build instructions; non-interactive mode trades review friction for automation.
- TPM unlocking is a convenience and measured-boot control, not a substitute for an offline recovery credential.
- A firmware reset, Secure Boot key change, TPM clear, or motherboard replacement can require the retained LUKS passphrase.

Read [docs/INSTALLATION.md](docs/INSTALLATION.md), [docs/SECURITY.md](docs/SECURITY.md), and [docs/RECOVERY.md](docs/RECOVERY.md) before relying on the installation for important data.
