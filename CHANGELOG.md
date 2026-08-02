# Changelog

## 0.2.0 - 2026-08-02

- Added a self-contained UEFI installer USB builder.
- Added two extracted official Arch live slots with current/recovery boot entries.
- Added PGP and SHA-256 verified Arch refresh into the non-running slot.
- Added GitHub-first repository refresh through immutable commit archives, without installing Git into the live environment.
- Added current and previous local repository snapshots from initial USB creation, plus exact source-commit provenance in the installed system.
- Added version-controlled machine profiles and a local emergency profile fallback.
- Added optional dependency-complete official and reviewed AUR package caches for fully offline installation.
- Centralised package selection for installation, cache creation and CI.
- Added online-first/force-offline live installer menu and cache verification.
- Made first-boot provisioning work without a network after a complete offline install.
- Added read-only USB fallback and interrupted Arch/package-cache update recovery.
- Added staged package-cache dependency resolution and flush-before-retire activation.
- Added USB, trust, recovery and customisation documentation and tests.

## 0.1.0 - 2026-07-12

- Initial vanilla Arch T480 workstation installer.
