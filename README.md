# Arch T480 Workstation

A reproducible vanilla Arch Linux workstation and custom installation-USB project for x86-64 UEFI systems, with a Lenovo ThinkPad T480 profile enabled by default.

The project treats the operating system as rebuildable configuration. It creates a bootable custom ArchISO, keeps a writable offline cache beside it, installs a compact Xfce/X11 system, provisions the requested applications, creates an owner-controlled Secure Boot chain, and enrols TPM2-backed LUKS unlocking while retaining a recovery passphrase.

> **Destructive:** both USB creation and workstation installation erase the selected whole disk. Verify model and serial number and use the non-destructive checks first.

## Version 0.3 highlights

- Restored a supported `build-usb.sh` workflow built on ArchISO's `releng` profile.
- Replaced the fragile `bootmnt`/`mason-arch` dependency with an immutable custom ISO plus a writable `ARCHWS_DATA` partition.
- Automatically launches `archws` on tty1 while retaining a normal root shell on failure.
- Defaults to a live Git ref and current Arch package sources, with fallback order live → persistent cache → embedded repository.
- Refreshes the Git mirror/bundle, current official Arch ISO backup, pacman databases, and configured official package cache before a live install.
- Supports a cache-only refresh from the USB menu or `build-usb.sh --refresh-only` without installing or rewriting the boot image; saved configuration and encrypted credentials are preserved unless explicitly changed.
- Adds guided configuration at build time and on the live USB.
- Adds an optional GnuPG-encrypted credential bundle with all missing values collected together before the build.
- Validates writable media metadata plus live Git URLs/refs instead of executing metadata as shell input.
- Stages LUKS/TPM credentials only inside a separate encrypted Btrfs subvolume excluded from root snapshots, then removes them after successful TPM enrolment.
- Retains the v0.2 fixes for multilib, Paru prompts, Ansible sudo, complete EFI signing, and resumable first boot.

## Baseline

- Vanilla Arch Linux, x86-64, UEFI/GPT only.
- Xfce on X11.
- `linux` and `linux-lts` Unified Kernel Images.
- LUKS2 encrypted Btrfs root with zstd compression.
- systemd-boot, `sbctl` owner keys, Secure Boot, and TPM2 PCR 7 with a PIN.
- NetworkManager, PipeWire, LightDM, zram, Snapper, TLP, thermald, fwupd, and SMART monitoring.
- Bash installation, Ansible provisioning, and PowerShell/VS Code user configuration.

## Requested applications

| Requirement | Package source |
|---|---|
| Microsoft Edge | `microsoft-edge-stable-bin` from AUR |
| Vim | `vim` from official repositories |
| PowerShell | `powershell-bin` from AUR |
| .NET | `dotnet-sdk` from official repositories |
| Visual Studio Code | `visual-studio-code-bin` from AUR |
| Docker | `docker`, Buildx, and Compose |
| Git | `git` |
| Steam | `steam`, GameMode, MangoHud, and explicit 32-bit Vulkan userspace |
| OneDrive | `onedrive-abraunegg` from AUR with managed config and user service |
| GitHub CLI | `github-cli` from official repositories |

## Build the installation USB

From an installed Arch system:

```bash
git clone <repository-url> arch-workstation
cd arch-workstation
./build-usb.sh --device /dev/sdX --configure
```

For an encrypted build-time credential bundle:

```bash
cp config/usb-secrets.json.example config/usb-secrets.json
chmod 0600 config/usb-secrets.json
vim config/usb-secrets.json

./build-usb.sh \
  --device /dev/sdX \
  --configure \
  --secure-file config/usb-secrets.json
```

Read [docs/USB.md](docs/USB.md) before selecting the device.

## Boot and install

Before booting the USB:

1. use UEFI-only mode;
2. enable the TPM/security chip;
3. disable Secure Boot;
4. clear Secure Boot keys so Setup Mode is enabled;
5. do not restore factory keys.

The `archws` menu starts automatically. Option 1 checks connectivity, offers `iwctl` when Wi-Fi is not yet connected, then uses the live repository and Arch package sources and refreshes the persistent cache before installation. Option 2 uses the cached project and official packages. The normal installer still requires the exact `ERASE /dev/...` confirmation.

After the installer enrols and signs the owner-controlled boot chain:

1. enter firmware setup;
2. enable Secure Boot without clearing or restoring keys;
3. boot Arch and log in;
4. run:

```bash
archctl finish
```

When the encrypted USB credential bundle supplied the LUKS passphrase and TPM PIN, `finish` uses the staged credentials automatically for TPM enrolment. Otherwise it prompts interactively. The long LUKS passphrase remains the recovery route.

## Refresh an existing USB without installing

From the live menu choose **Refresh all offline caches without installing**, or from Arch:

```bash
./build-usb.sh --refresh-only --device /dev/sdX
```

This refreshes the writable cache only and preserves the USB's existing installation configuration and encrypted credential bundle. Add `--configure`, `--set KEY=VALUE`, `--secure-file PATH`, or `--no-secrets` only when you deliberately want to change those items. Rebuild the USB normally to replace the immutable custom boot ISO.

A USB made by v0.1/v0.2 with the old `mason-arch`/`bootmnt` arrangement cannot be converted with `--refresh-only`; it must be erased and rebuilt once with v0.3.

## Installed-system commands

```text
archctl finish              Resume the complete first-boot workflow
archctl status              Show the detected setup stage and next action
archctl apply               Reapply desired system and user configuration
archctl provision           Alias for archctl apply
archctl auth [TARGET]        Run or inspect supported application sign-ins
archctl secure-boot         Enrol/sign or repair the Secure Boot chain
archctl tpm-enroll          Enrol TPM2 unlocking after Secure Boot is active
archctl tpm-remove          Return to passphrase-only unlocking
archctl recovery-key        Add and print a separate LUKS recovery key
archctl verify              Run the strict installation/security audit
archctl snapshot TEXT       Create a manual Snapper root snapshot
archctl update              Update packages, rebuild UKIs, sign, and verify
```

The installed repository also exposes `arch-workstation-build-usb` as a symlink to `build-usb.sh`.

## Repository layout

```text
.
├── build-usb.sh              custom ArchISO/USB entry point
├── usb/                      builder, launcher, cache, config, and secrets tooling
├── install.sh                destructive workstation installer
├── start.sh                  live/install and installed-system compatibility entry point
├── upgrade-existing.sh       safe migration of installed automation
├── archctl                   installed-system command dispatcher
├── config/                   machine policy and secret-file example
├── scripts/install/          preflight, disk, base, and chroot stages
├── scripts/security/         state, signing, TPM, recovery, and verification
├── ansible/                  idempotent workstation roles
├── powershell/               PowerShell profile/module configuration
├── dotfiles/                 Git and Vim defaults
├── vscode/                   settings and extension allow-list
├── docs/                     USB, installation, security, recovery, and design
└── tests/                    static and non-destructive functional checks
```

## Important limits

- Whole-disk installation only; no dual boot or partition preservation.
- The offline cache guarantees configured official Arch packages, not complete AUR/upstream payload availability.
- The custom ISO is immutable while booted; cache refresh does not rewrite it.
- A public credential-free HTTPS Git URL is the simplest live source. Private repository authentication is not embedded automatically.
- Snapshots are not backups.
- Docker-group membership is root-equivalent.
- Firmware key changes, TPM clearing, or motherboard replacement can require the retained LUKS passphrase.

After `archctl finish`, the next graphical login offers supported application sign-ins. OneDrive authentication performs a dry run and initial sync before safely linking `Documents`, `Pictures`, and `Videos`; existing local folders are retained in dated backups.

Read [docs/USB.md](docs/USB.md), [docs/INSTALLATION.md](docs/INSTALLATION.md), [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md), [docs/SECURITY.md](docs/SECURITY.md), and [docs/RECOVERY.md](docs/RECOVERY.md) before relying on the installation for important data.
