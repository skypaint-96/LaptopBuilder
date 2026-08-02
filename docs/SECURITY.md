# Security model

## What the design protects

The installed workstation combines:

- LUKS2 encryption with a retained human passphrase and optional recovery key;
- signed Unified Kernel Images and systemd-boot under owner-controlled Secure Boot keys;
- TPM2 enrollment bound to PCR 7, with a PIN by default;
- root-owned installed configuration and source snapshot;
- explicit destructive and firmware-enrollment confirmations;
- A/B live installer recovery and previous repository fallback.

It reduces accidental loss and makes unattended modification of the installed boot chain harder. It does not replace personal-data backups or protect a running, unlocked administrator session.

## GitHub configuration is root code

The USB executes installer code from the configured repository as root. A moving branch therefore delegates installation authority to:

- the GitHub account and repository permissions;
- branch protection and review practices;
- every dependency or action used to modify that repository.

The loader verifies structure and Bash syntax, not intent. A malicious but syntactically valid commit remains malicious.

Use a repository you control, enable strong account authentication and review diffs. The loader resolves a moving ref to a full commit first and downloads that immutable commit archive, avoiding a branch-changing-between-downloads race. For release-grade installs, set `REPO_PINNED_COMMIT` to a full reviewed hash. The pin prevents a branch update from being accepted until you deliberately change it.

Only public HTTPS GitHub URLs are supported. Do not put tokens in `config/usb.conf`; the USB partition is not encrypted.

## USB trust boundary

The USB is writable FAT32 so firmware can boot it and the live system can refresh it. Anyone with physical write access can replace files and recompute adjacent SHA-256 manifests.

The manifests and A/B generations protect primarily against:

- failed downloads;
- interrupted writes;
- accidental corruption;
- a structurally incomplete update.

They are not a separate cryptographic root of trust. Keep the USB physically controlled. Rebuild it from a trusted repository/host after loss of custody.

When the live system cannot remount the USB read-write, the loader enters a read-only fallback: no cache is replaced, but the existing verified slots, repository generations and package caches remain usable. Read-only operation prevents that session from refreshing content; it does not make previously stored content inherently trustworthy.

The installer USB itself is booted with Secure Boot disabled. The target's Secure Boot design begins after installation; do not confuse the unsigned/mutable installer trust boundary with the signed installed boot chain.

## Official Arch image verification

A live refresh requires both:

- the current published SHA-256 value; and
- the detached official Arch ISO PGP signature checked by `pacman-key`.

Creation on a non-Arch host may lack `pacman-key`; in that case the creator checks the HTTPS SHA-256 list and warns. Booting the resulting official Arch environment and refreshing once performs the full PGP check before replacing a slot.

New images are written only to the non-running slot. The slot is checked for the expected kernel, initramfs, squashfs and CMS signature files before it is selected for the next boot.

## Offline package trust

Official package downloads use normal Arch signature policy at cache-build time. AUR package files are locally built from reviewed community recipes and are normally unsigned.

The generated offline pacman configuration trusts the local repositories because the AUR packages have no separate package-signing key. The same-filesystem manifests detect damage but not malicious replacement by someone who can also rewrite the manifest. Treat the complete USB as trusted installation media.

Review every AUR PKGBUILD, `.SRCINFO`, source URL and update diff. `AUR_NONINTERACTIVE=true` deliberately removes this human gate and is not the recommended workstation default.

## Configuration and secrets

`profiles/t480.conf`, `config/install.conf` and `config/usb.conf` are sourced by Bash. They must contain policy, not literal secrets.

Passwords are prompted into shell variables before target erasure and cleared after use. Optional secret files must be root-readable with mode `0400` or `0600`, are not copied to the target and must not be stored on the USB's FAT partition.

Never commit:

- LUKS passphrases or recovery keys;
- GitHub tokens;
- SSH private keys;
- Secure Boot private keys;
- TPM recovery material;
- client or employer confidential data.

The installed configuration is `/etc/arch-installer/install.conf`, owner `root:wheel`, mode `0640`. One-shot secret paths, erase confirmation, non-interactive flags, live USB cache paths and firmware enrollment confirmation are cleared during installation.

## Secure Boot keys

`archctl secure-boot` requires firmware Setup Mode and an exact phrase before enrolling keys. Microsoft UEFI certificates are retained by default for compatibility.

Back up `/var/lib/sbctl/keys` encrypted and offline. Possession of these private keys permits signing code trusted by the machine. Do not store the backup on the installer USB beside the system it protects.

The update path refuses kernel/boot work when `/efi`, the expected key pair or `/etc/kernel/uki.conf` is missing while Secure Boot is active or expected.

## TPM2 limitations

TPM unlock improves resistance to simple offline theft but is not a substitute for the LUKS passphrase. PCR 7 binds to Secure Boot policy; firmware or key changes can intentionally break automatic unlocking.

The default PIN adds user presence and limits a stolen powered-off laptop from relying solely on measured state. Keep the ordinary passphrase and printed recovery key. Test passphrase fallback after every TPM re-enrollment.

Do not clear the TPM or delete LUKS slots as a first troubleshooting step.

## Docker and local privilege

Membership of the `docker` group is effectively root-equivalent because members can mount host filesystems or launch privileged containers. `DOCKER_ADD_USER_TO_GROUP=true` chooses convenience over strict privilege separation. Set it false to require `sudo docker` or adopt a reviewed rootless design.

## SSD discard

`ENABLE_SSD_TRIM=true` allows discard through dm-crypt and enables periodic trim. It can reveal which encrypted blocks are unused. Set it false when hiding allocation patterns matters more than SSD maintenance.

## Recommended operating practices

- Keep both `linux` and `linux-lts` bootable.
- Run `archctl update`, not partial package upgrades.
- Run `sudo archctl verify` after security or boot changes.
- Test both TPM/PIN and passphrase unlock.
- Back up personal data, the Git repository, LUKS recovery key and Secure Boot keys through separate channels.
- Keep at least one known-good installer/recovery USB or the means to rebuild it.
