# Customising the repository

## Source-of-truth files

For the USB workflow, make normal machine changes in:

```text
profiles/t480.conf
```

Commit and push that file. `config/usb.conf` is intentionally ignored because it identifies your GitHub URL and local update preference; it contains no secrets. `MASON-ARCH/config/install.conf` is only the last-resort local profile copied during USB creation.

A configuration file is sourced by Bash. Treat every change as executable code.

## Common switches

| Variable | Effect |
|---|---|
| `CPU_VENDOR` | Intel or AMD microcode |
| `GPU_VENDOR` | Intel, AMD or generic Mesa userspace |
| `KERNELS` | Kernel packages and UKIs |
| `EXTRA_OFFICIAL_PACKAGES` | Additional official Arch package names |
| `ENABLE_AUR` / `AUR_PACKAGES` | Reviewed AUR application list |
| `AUR_HELPER_PACKAGE` | AUR package that supplies the configured helper command |
| `ENABLE_DOCKER` | Docker engine and plugins |
| `DOCKER_ADD_USER_TO_GROUP` | Convenient but root-equivalent daemon access |
| `ENABLE_GAMING` | Steam, GameMode, MangoHud and 32-bit graphics stack |
| `ENABLE_SNAPSHOTS` | Snapper and pacman hooks |
| `ENABLE_T480` | T480 power, thermal, firmware and SMART policy |
| `ENABLE_SECURE_BOOT` | Owner-key Secure Boot workflow |
| `ENABLE_TPM` / `TPM_PCRS` | TPM2 unlock policy |

## Add official software

The simplest extension is a profile-only change:

```bash
EXTRA_OFFICIAL_PACKAGES="audacity keepassxc libreoffice-fresh"
```

The central package generator automatically includes these names in online installation, offline-cache building and validation. Refresh the USB package cache after changing the selection:

```bash
sudo ./usb/refresh-packages.sh \
  --usb-root /run/archiso/bootmnt \
  --install-config /run/mason-installer/repo/config/install.conf
```

For a package that is an intentional part of a repository role rather than a personal extra, add it to `scripts/lib/packages.sh` and the corresponding Ansible role policy.

## Add an AUR application

Add a reviewed package base name:

```bash
AUR_PACKAGES="microsoft-edge-stable-bin visual-studio-code-bin powershell-bin another-package"
```

Online provisioning presents `paru` review prompts. Offline caching prints each PKGBUILD and `.SRCINFO` and requires `BUILD package-name` before compiling it.

The default helper package is `paru`. It is compiled during cache refresh and included in the complete offline cache, so an offline-installed workstation still has the normal `paru` command for later use.

The AUR is user-maintained. Name resolution and successful compilation are not a security review. Inspect source URLs, install scripts and diffs on every refresh.

## Software distributed only as `.deb`

Do not install a Debian package directly with `pacman`. Use this order:

1. official Arch repository;
2. reviewed AUR package;
3. upstream AppImage or Flatpak;
4. a small maintained Arch PKGBUILD;
5. conversion of a `.deb` only as a temporary, inspected last resort.

For AudioMoth Configurator specifically, upstream provides an AppImage for distributions that do not use Debian packages. Store any chosen AppImage installation script in this Git repository, pin a release/checksum where possible and run it from a reviewed user-level provisioning step rather than modifying the base package cache as if it were an Arch package.

## Another x86-64 machine

Generic Intel:

```bash
CPU_VENDOR="intel"
GPU_VENDOR="intel"
ENABLE_T480=false
```

AMD CPU and graphics:

```bash
CPU_VENDOR="amd"
GPU_VENDOR="amd"
ENABLE_T480=false
```

Generic Mesa without gaming:

```bash
GPU_VENDOR="generic"
ENABLE_GAMING=false
```

NVIDIA proprietary/hybrid systems need a dedicated package, module, UKI signing and power-management design. Do not weaken validation and assume the Intel profile applies.

## Dotfiles

Managed defaults:

- `dotfiles/vimrc` -> `~/.vimrc`
- `dotfiles/gitconfig` -> `~/.gitconfig`
- `powershell/profile.ps1` -> managed PowerShell loader
- `vscode/settings.json` and `vscode/extensions.txt`

Personal Git identity belongs in `~/.gitconfig.local`. Personal PowerShell overrides belong in:

```text
~/.config/powershell/profile.local.ps1
```

Do not commit SSH private keys, passwords, recovery keys, access tokens or `sbctl` private keys.

## Desktop or storage changes

Xfce/X11 is a coordinated baseline, not merely a package name. A replacement must update login/session, portals, polkit, locking, power management, verification and recovery documentation together.

The storage design deliberately owns a whole disk. Dual boot, hibernation, LVM, RAID, a separate partitioned home or another filesystem requires a separate migration and recovery design.
