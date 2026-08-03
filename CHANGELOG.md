# Changelog

## 0.3.2

- Replace `sgdisk` partition creation on ISOHybrid USB media with `sfdisk` append logic.
- Relocate a GPT backup header explicitly when the written ArchISO uses GPT.
- Support both GPT and DOS/MBR ISOHybrid layouts.
- Detect the newly appended partition by device topology before formatting it.
- Verify the `ARCHWS_DATA` filesystem label after creation.


## 0.3.0 - 2026-08-03

- Restored USB building as a first-class repository workflow through `build-usb.sh` and ArchISO `releng`.
- Added an immutable custom boot ISO plus a writable `ARCHWS_DATA` partition instead of the obsolete `bootmnt`/`mason-arch` dependency.
- Added automatic tty1 launch with a safe fallback to the normal live root shell.
- Added live Git/Arch installation with persistent cache refresh and live -> cache -> embedded project fallback.
- Added offline project bundle, official Arch ISO backup, pacman sync databases, package manifest, and complete configured official-package cache.
- Added cache-only refresh from both the live menu and an installed Arch system.
- Added guided build/live configuration and ISO-only output.
- Added optional AES-256 GnuPG-encrypted build-time credentials with mode checks, one-time live decryption into `/run`, and no plaintext username duplication on media; guided live edits retain the placeholder while a bundle exists.
- Collected LUKS, account, and TPM credentials together before destructive installation.
- Added a separate encrypted `@credentials` Btrfs subvolume excluded from root snapshots for temporary first-boot TPM credentials.
- Added non-interactive TPM enrolment through systemd service credentials and automatic credential removal after token, initramfs, UKI, and signature verification.
- Added live/offline preflight modes and host-cache-aware `pacstrap`.
- Added USB, cache, encrypted-secret, configuration, and staged-credential regression tests.
- Added USB API compatibility checks so an obsolete live branch falls back to the persistent or embedded project.
- Added an upfront network check with `iwctl` support so default live mode does not silently become a cached install.
- Made host-side cache refresh preserve saved configuration and encrypted credentials unless an explicit replacement/removal option is supplied.
- Added stale-signature removal, ISO-region byte comparison, ext4 checking, and post-write read-back verification.
- Added udev settling and bounded retry logic before mounting the writable `ARCHWS_DATA` partition during live boot.
- Added exact offline transaction payload verification before target-disk erasure.
- Excluded plaintext USB secret inputs, encrypted bundles, ISO images, and builder output from installed, embedded, cached, and upgraded source snapshots.
- Kept secret values off command lines, required a stronger USB-bundle passphrase, and rejected symlink secret inputs.
- Parsed writable media metadata as an allow-listed base64 format and validated live Git URLs/refs before passing them to Git.
- Propagated cache-refresh failures correctly, started `iwd` before opening `iwctl`, and rejected secret inclusion for ISO-only builds that have no writable data partition.
- Made the offline bootstrap genuinely network-independent by resolving a complete cached package-file transaction and installing it through `pacstrap -U` instead of sync mode.
- Strengthened USB erasure guards to reject devices backing the running system, active swap, the repository, configuration, secret input, or generated ISO.
- Made staged Git changes count as dirty source snapshots, rejected credential materialisation outside temporary runtime trees, and made invalid writable metadata fall back to the immutable ISO copy.
- Prevented cache-only secret removal from leaving the encrypted-build placeholder username as the real installation account.
- Excluded secret/config/build artefacts even when they have accidentally been force-added to the source Git index.

## 0.2.0 - 2026-08-02

- Added a resumable `archctl finish`/`archctl status` first-boot state machine.
- Required Secure Boot Setup Mode during preflight by default and prepared owner keys plus the complete signed EFI set during installation.
- Changed EFI signing from a fixed/partial set to discovery, `sign --save`, `sign-all`, and strict verification of every `.efi` under `/efi/EFI`.
- Resolved and synchronised `multilib` before any destructive disk action or package installation.
- Added pre-erasure resolution of the complete configured official package set and AUR allow-list.
- Switched the default helper bootstrap to `paru-bin`, removing the Rust/Cargo provider prompt and Paru source compile.
- Added optional non-interactive AUR allow-list installation and package provisioning defaults.
- Fixed Ansible privilege escalation by using one sudo session and running the playbook through that authenticated root context.
- Re-signed and verified all boot assets after provisioning and normal updates.
- Added `start.sh` compatibility and `upgrade-existing.sh` with installed-configuration preservation and backups.
- Added first-login guidance, migration documentation, and regression assertions for the physical-install failures.
- Made TPM completion require both the LUKS2 token and matching initramfs crypttab configuration, with automatic repair after partial runs.
- Clarified final Setup Mode status and removed the obsolete Secure Boot confirmation setting.
- Re-enrols owner keys when firmware remains in Setup Mode after an interrupted key operation.
- Automatically drops accidental sudo use for normal-user workflows and makes firmware reboot requests non-fatal.
- Validates the complete PK/KEK/db key hierarchy and safely preserves partial sbctl state before regeneration in Setup Mode.
- Fixed Snapper configuration registration to write a valid shell assignment rather than a literal `\n`.
- Made CI install Ansible Core so playbook syntax is always exercised.
- Made existing-install migration roll back both the automation tree and edited policy file if staging or activation fails.

## 0.1.1 - 2026-08-02

- Fixed installation failure for Steam and `lib32-*` packages by enabling and synchronising the live ISO `multilib` repository before `pacstrap`.

## 0.1.0 - 2026-07-12

- Initial T480-focused Arch workstation installer.
- Added LUKS2, Btrfs, UKI, systemd-boot, Secure Boot, and TPM2 workflow.
- Added Xfce/X11 desktop, Ansible roles, requested developer/gaming applications, Snapper, TLP, and CI checks.
