# Changelog

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
