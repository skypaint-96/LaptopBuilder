# Package and application sources

## Selection source

`scripts/lib/packages.sh` generates the official package set from the machine profile. The same function is used by:

- online `pacstrap` installation;
- the offline package-cache builder;
- offline completeness validation;
- current Arch package-resolution CI.

This prevents the installer, cache and documentation from maintaining unrelated lists.

Personal official additions belong in:

```bash
EXTRA_OFFICIAL_PACKAGES="package-one package-two"
```

AUR applications are selected by:

```bash
AUR_PACKAGES="microsoft-edge-stable-bin visual-studio-code-bin powershell-bin"
```

The offline cache also includes the configured helper package:

```bash
AUR_HELPER="paru"
AUR_HELPER_PACKAGE="paru"
```

`paru` is built against the current Arch `pacman`/`libalpm`, avoiding reliance on an older precompiled helper binary. Its build dependencies increase cache-refresh downloads but are not required for normal use after installation.

## Included categories

The default official set includes:

- Arch base, both kernels, firmware, microcode and build tools;
- LUKS/Btrfs/UEFI/UKI/Secure Boot/TPM tooling;
- Xorg, Xfce, LightDM, PipeWire, Bluetooth and desktop integration;
- NetworkManager, SSH client/server package and common command-line tools;
- Ansible, .NET SDK, CMake, Ninja, ShellCheck, Git and Vim;
- Docker engine, Buildx and Compose when enabled;
- Steam, GameMode, MangoHud and explicit 32-bit Intel/AMD graphics libraries when gaming is enabled;
- Snapper and T480 firmware/power/thermal/storage tools when their profiles are enabled.

Microsoft Edge, Microsoft's Visual Studio Code build and PowerShell binary packages are supplied through reviewed AUR recipes because they are not in the official repositories.

## Online installation

The complete official set is installed before the first target boot. `archctl provision` therefore focuses on configuration and services. When online, it also performs a full system upgrade and installs/reviews missing AUR applications.

## Offline repositories

`usb/refresh-packages.sh` builds flat local pacman repositories:

```text
MASON-ARCH/cache/pacman/
  workstation.db
  *.pkg.tar.zst
  packages.requested.txt
  SHA256SUMS

MASON-ARCH/cache/aur/
  workstation-aur.db
  *.pkg.tar.zst
  packages.requested.txt
  SHA256SUMS
```

The AUR stage builds the helper and configured applications first so any official build dependencies introduced by AUR recipes are added to the official cache. The official stage then downloads the complete dependency closure.

Both new cache directories are staged and verified before the old pair is replaced. A failed activation restores the previous pair.

The builder also loads the staged databases through a separate empty pacman database and asks pacman to resolve the complete configured workstation. This catches an AUR dependency that happened to exist in the live environment but was not actually present in the USB cache. Staged data is flushed before the `.old` rollback generation is removed.

An `--official-only` refresh intentionally produces an official-only generation. If an older AUR cache exists, it is retired with the old pair rather than retained beside a newly generated, potentially incompatible official repository.

Before disk erasure, force-offline installation:

1. verifies every file against `SHA256SUMS`;
2. loads both repository databases through a generated pacman configuration;
3. asks pacman to resolve every configured official and AUR package;
4. aborts when any package or dependency is absent.

## Trust model

Official package files are downloaded through pacman with normal Arch signature policy during cache creation. AUR packages are built locally from user-maintained PKGBUILDs after review.

The USB's SHA-256 manifests detect corruption and interrupted copies. They are stored next to the files on the same writable FAT filesystem, so they do **not** prove authenticity against an attacker with physical write access. Rebuild or refresh the cache from a trusted Arch environment when the USB's custody is uncertain.

The offline generated pacman configuration permits the local packages because AUR packages are normally unsigned. This makes physical control and review of the USB especially important.

## Updates

An offline cache is a point-in-time repository. It does not turn Arch into a fixed-release distribution. Refresh it before a reinstall and after profile/package changes:

```bash
sudo ./usb/refresh-packages.sh \
  --usb-root /run/archiso/bootmnt \
  --install-config /run/mason-installer/repo/config/install.conf
```

After installation, ordinary maintenance remains:

```bash
archctl update
```

Do not perform partial Arch upgrades or install a single old cached package into a substantially newer online system without completing a coherent full upgrade.
