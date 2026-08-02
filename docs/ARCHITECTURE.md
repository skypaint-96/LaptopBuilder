# Architecture

## Design goals

The workstation is a reproducible result of versioned policy, not a precious disk image. The installer USB adds local recovery generations so loss of Internet or a bad update does not remove the ability to boot.

The design distinguishes three operations:

- `usb/create-usb.sh` is destructive to one selected USB disk.
- `install.sh` is destructive to one selected target disk and is intentionally not idempotent.
- refresh, provision, configuration, signing, verification and update operations are intended to be repeatable.

## End-to-end flow

```text
Existing Linux host
  -> create one UEFI FAT32 installer USB
       -> GRUB removable loader
       -> Arch live slot A
       -> Arch live slot B
       -> repository current + previous
       -> optional package repositories

USB boot
  -> stable local start.sh
       -> GitHub update when valid/reachable
       -> otherwise current/previous local snapshot
       -> repository machine profile, otherwise local profile
       -> check official current Arch ISO
       -> write/verify non-running live slot
       -> switch next boot only after success

Target install
  -> GPT
  -> ESP + LUKS2
  -> Btrfs subvolumes
  -> complete official package set
  -> offline AUR binaries when applicable
  -> UKIs + systemd-boot

First installed boot
  -> Ansible/service/dotfile provisioning
  -> online AUR review when not already cached
  -> Secure Boot owner-key enrollment and signing
  -> recovery key
  -> TPM2 PCR 7 + PIN enrollment
```

## USB A/B model

`arch-a` and `arch-b` are complete extracted official Arch live trees. GRUB reads `MASON-ARCH/state/active-slot.cfg` to select the normal entry and offers the other slot as recovery.

The refresh command identifies the running slot from the kernel command line. It downloads and verifies the current ISO, extracts to `arch-OTHER.new`, validates required kernel/initramfs/squashfs/signature files, rotates the old non-running slot and only then changes `active-slot.cfg`.

The running slot is never changed. A power or download failure therefore leaves it bootable. FAT32 does not provide transactional updates, so the sequence uses same-filesystem staging, verification and rollback directories rather than claiming true atomicity.

## Repository generations

The stable USB loader resolves the configured branch, tag or pin to a full GitHub commit and downloads that immutable commit archive. It accepts the repository only after:

- the configured ref or pinned commit resolves;
- required installer files exist;
- the configured machine profile exists;
- every Bash script passes `bash -n`;
- a local source archive is created and checksumed.

The accepted `current` archive rotates to `previous`. Startup verifies current first, then previous. The new repository code runs from tmpfs under `/run/mason-installer/repo`; the cache archive remains the source generation. The accepted commit identifier is passed through installation and written to `/opt/arch-workstation/BUILD_COMMIT`.

## Storage layout on the target

| GPT partition | Format | Purpose |
|---|---|---|
| 1 | FAT32, 1 GiB | EFI System Partition mounted at `/efi` |
| 2 | LUKS2 | Encrypted Btrfs container |

Btrfs subvolumes:

| Subvolume | Mount point | Purpose |
|---|---|---|
| `@` | `/` | Operating-system root |
| `@home` | `/home` | User data and configuration |
| `@var_log` | `/var/log` | Logs independent of root rollback |
| `@pkg` | `/var/cache/pacman/pkg` | Package cache independent of root rollback |
| `@snapshots` | `/.snapshots` | Snapper storage |

Mounts use `noatime` and `compress=zstd:1`. zram replaces a disk swap partition. Hibernation is deliberately omitted.

## Installed boot chain

```text
UEFI trust database
  -> signed systemd-boot
       -> signed Unified Kernel Image
            -> kernel + microcode + initramfs + command line
                 -> systemd initramfs unlocks LUKS2
                      -> Btrfs @ root
```

The normal and LTS UKIs are:

```text
/efi/EFI/Linux/arch-linux.efi
/efi/EFI/Linux/arch-linux-lts.efi
```

## Configuration layers

1. `config/usb.conf` controls GitHub, update and cache behaviour on the installer USB.
2. `profiles/t480.conf` is the version-controlled machine policy.
3. `MASON-ARCH/config/install.conf` is the emergency local fallback.
4. Bash owns disk creation, base installation and early boot.
5. `scripts/lib/packages.sh` generates the complete package set for online install, offline caching and CI resolution.
6. Ansible owns repeatable services, machine policy and dotfiles after first boot.
7. PowerShell and VS Code scripts own user-level configuration.
8. `archctl` exposes stable operational commands.

## Package-source model

Online target installation uses official Arch repositories for the complete official set. AUR applications are reviewed and built later by `paru`.

Offline installation uses two local pacman repositories:

- `workstation` for official package files and dependencies;
- `workstation-aur` for previously reviewed/built AUR package files.

Cache creation validates the staged pair against an empty pacman database before activation, flushes the new files, and retains `.old` directories until the activated generation has passed verification. Startup recognises and repairs the supported interrupted-activation states.

The USB manifest detects corruption and incomplete transfers. It is not a signature from a separate trust root; physical write access can replace content and its manifest.

## Supported boundaries

Implemented:

- x86-64 UEFI;
- Intel or AMD CPU microcode;
- Intel, AMD or generic Mesa graphics profiles, with gaming limited to Intel/AMD;
- T480 profile;
- optional Docker, gaming, snapshots, Bluetooth and SSH server;
- online-first and complete offline target installation;
- local A/B live recovery and repository generation fallback.

Not implemented:

- dual boot or partition preservation;
- BIOS/CSM;
- NVIDIA proprietary/hybrid graphics;
- hibernation;
- cryptographic remote attestation of the Git branch;
- tamper-resistant USB storage;
- automatic booting of Btrfs snapshots;
- unattended Secure Boot key enrollment.
