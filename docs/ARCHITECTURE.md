# Architecture

## Goals

The repository treats the workstation as a reproducible result of versioned configuration rather than as a disk image. The design favours conventional Arch components, transparent scripts, a recovery passphrase, and staged security changes.

It has two different idempotency models:

- `install.sh` is intentionally destructive and is **not** idempotent. It owns one whole disk.
- `archctl finish`, provisioning, the Ansible roles, PowerShell/VS Code configuration, signing, TPM enrolment, verification, and updates are designed to be re-run.

## Build stages

```text
Custom Arch workstation USB, firmware already in Setup Mode
    |
    +-- live launcher
    |       live Git/Arch sources by default
    |       persistent cache or embedded fallback
    |       optional encrypted credential bundle -> RAM
    |
    +-- Bash preflight
    |       firmware/TPM/disk checks
    |       multilib sync
    |       complete official + AUR package-name resolution
    |
    +-- Whole-disk installation
    |       GPT -> ESP + LUKS2 -> Btrfs
    |       base system -> Xfce/X11 -> systemd-boot -> UKIs
    |       sbctl owner-key enrollment -> sign/register every EFI binary
    |
Firmware: enable Secure Boot without replacing the enrolled keys
    |
First boot with the retained LUKS passphrase
    |
    +-- `archctl finish`
            one sudo session
            Ansible official-package/service provisioning
            non-root AUR, VS Code, and PowerShell configuration
            complete boot-chain rebuild/sign/verification
            TPM2 enrollment (PCR 7 + optional PIN)
            strict final audit
```

Secure Boot owner-key preparation happens before first boot, while firmware is already in Setup Mode. TPM enrollment remains after the first verified Secure Boot boot so the token is bound to the intended measured policy.

## Installation-media architecture

The custom USB has an immutable hybrid ArchISO region and a writable ext4 partition labelled `ARCHWS_DATA`. The immutable layer contains the launcher and a tracked embedded repository snapshot. The writable layer contains machine configuration, optional encrypted credentials, Git mirror/bundle, the current official Arch ISO backup, pacman sync databases, package files, manifests, logs, and refresh state.

At boot, project selection is evidence-based and ordered: live configured Git ref, persistent bundle, then embedded copy. A missing data partition does not prevent the embedded launcher from running. A live installation refreshes persistent caches before the normal destructive preflight. An offline installation restores cached sync databases, bind-mounts the package cache, verifies every package payload, and bootstraps the base system through pacstrap's local-file (`-U`) mode so no repository refresh is attempted.

The boot ISO cannot safely rewrite itself while executing. Cache-only refresh updates `ARCHWS_DATA`; rebuilding the USB replaces the immutable ArchISO. See [USB.md](USB.md).

## Platform baseline

| Component | Choice | Reason |
|---|---|---|
| Distribution | Vanilla Arch Linux | Direct Arch packaging and documentation; no derivative-specific installer state |
| Architecture | x86-64 | Matches the T480 and requested modular x64 scope |
| Firmware | UEFI/GPT only | Modern boot path required by the Secure Boot and UKI design |
| Desktop | Xfce | Mature, relatively small, and conventional |
| Display system | X11 | Broad compatibility; Xfce's Wayland path remains experimental rather than the default baseline |
| Kernels | `linux` and `linux-lts` | Current hardware/software support plus a second kernel for recovery |
| Root filesystem | Btrfs | Compression, subvolumes, and Snapper snapshots without a separate volume manager |
| Encryption | LUKS2 | Supported by systemd early boot and TPM token enrollment |
| Boot manager | systemd-boot | Small UEFI-native loader with automatic UKI discovery |
| Initramfs/UKI | mkinitcpio + ukify | Arch-native generation of self-contained EFI kernel images |
| Provisioning | Ansible Core | Desired-state-style, readable local roles without a permanent agent |
| User automation | PowerShell 7 | Cross-platform profile and optional module management |
| AUR helper | `paru` via `paru-bin` | Small explicit AUR allow-list; automated prompts are configurable |

## Storage layout

The installer consumes the configured whole disk.

| GPT partition | Typical device | Format | Mount/use |
|---|---|---|---|
| 1 | `/dev/nvme0n1p1` | FAT32, 1 GiB | EFI System Partition at `/efi` |
| 2 | `/dev/nvme0n1p2` | LUKS2 | Encrypted container for Btrfs |

Inside the opened LUKS mapping:

| Subvolume | Mount point | Purpose |
|---|---|---|
| `@` | `/` | Operating system root |
| `@home` | `/home` | User data and configuration |
| `@var_log` | `/var/log` | Logs survive root rollback independently |
| `@pkg` | `/var/cache/pacman/pkg` | Package cache survives root rollback independently |
| `@snapshots` | `/.snapshots` | Snapper snapshot storage |
| `@credentials` | `/var/lib/arch-workstation/pending-credentials` | Temporary first-boot TPM credentials, isolated from root snapshots |

Mount options use `noatime` and `compress=zstd:1`. Hibernation is deliberately omitted; zram provides compressed swap without adding encrypted Btrfs swapfile and resume complexity.

When `ENABLE_SSD_TRIM=true`, weekly `fstrim.timer` is enabled and the dm-crypt mapping permits discard propagation. See the leakage trade-off in [SECURITY.md](SECURITY.md).

## Boot chain

```text
UEFI firmware trust database
    -> signed systemd-boot EFI binary
        -> signed Unified Kernel Image in /efi/EFI/Linux
            -> kernel + microcode + initramfs + kernel command line
                -> systemd initramfs unlocks LUKS2
                    -> Btrfs subvolume @ mounted as root
```

Each configured kernel receives a UKI:

```text
/efi/EFI/Linux/arch-linux.efi
/efi/EFI/Linux/arch-linux-lts.efi
```

systemd-boot discovers these automatically. The normal kernel is the default; the LTS image remains selectable from the boot menu.

The repository configures mkinitcpio's systemd-based hooks, embeds microcode, and uses `/etc/crypttab.initramfs`. Once owner keys exist, `/etc/kernel/uki.conf` tells ukify where the Secure Boot private key and certificate live, while `sbctl` also signs and records all EFI binaries for future re-signing.

## Configuration layers

1. A reviewed local `config/install.conf` contains machine and policy choices during installation. The installed single source of truth is `/etc/arch-installer/install.conf`, with a repository symlink pointing to it.
2. Bash creates the storage, base operating system, users, early boot, initial services, and enough desktop policy/keyring integration to reconnect networking before provisioning.
3. `ansible/site.yml` composes modular roles for common tools, desktop integration, development, Docker, gaming, snapshots, and T480 settings.
4. `scripts/install-aur.sh` handles the explicitly allowed AUR packages as the non-root user.
5. `powershell/Configure-Workstation.ps1` installs a managed profile loader and optional modules.
6. `scripts/configure-vscode.sh` installs deterministic user settings and extension IDs.
7. `archctl` exposes stable operational commands after installation.

## Package-source policy

Official Arch repositories are used whenever a package exists there. The requested Microsoft desktop applications are represented by AUR packages:

- `microsoft-edge-stable-bin`
- `visual-studio-code-bin`
- `powershell-bin`

The AUR is not an official binary repository. The default workflow bootstraps `paru-bin` and builds/installs the explicit allow-list as the normal user, using the existing sudo session only where package installation requires it. Routine review prompts are suppressed by default for reduced intervention; `AUR_NONINTERACTIVE=false` restores manual review.

For Steam, the gaming role installs an explicit Intel or AMD native and 32-bit Vulkan provider before installing `steam`. This prevents an ambiguous virtual-driver dependency from selecting an unsuitable provider. Gaming therefore requires multilib and does not accept the generic GPU profile.

## Modularity boundaries

The installer currently supports:

- Intel or AMD x86-64 CPU microcode profiles;
- Intel, AMD, or generic open-source graphics userspace profiles, with gaming limited to the explicit Intel and AMD profiles;
- optional Docker, gaming, snapshots, Bluetooth, SSH server, and T480 policy;
- configurable AUR and user-tool stages.

The following are intentionally not implemented:

- dual boot or preserving existing partitions;
- BIOS/CSM boot;
- NVIDIA proprietary/hybrid graphics;
- hibernation;
- remote fleet management;
- automatic rollback boot entries;
- firmware Setup Mode entry or Secure Boot enforcement without physical firmware interaction.

These limits keep the first version reviewable and reduce destructive ambiguity.

## Resumable first-boot state machine

`archctl status --stage` derives state from real evidence rather than a linear script counter: the provisioning marker, Setup Mode, local owner keys, complete EFI verification, active Secure Boot, and a LUKS2 systemd TPM token. `archctl finish` repeatedly applies the next safe transition and can be rerun after a reboot or interrupted package operation.

Fresh installs normally enter first boot with the Secure Boot keys and files already prepared. The expected path is therefore `provision` -> `enroll-tpm` -> `complete` when Secure Boot was enabled before boot.
