# Migrating an existing 0.1 installation

Version 0.2 can replace the automation on a working 0.1 installation without reinstalling Arch or changing LUKS, Secure Boot, TPM, user data, or package state.

## Upgrade

Download and verify the 0.2 release, then extract it somewhere outside `/opt/arch-workstation`, for example in `~/Downloads`.

```bash
cd ~/Downloads/arch-t480-workstation
./upgrade-existing.sh
```

The script elevates itself and:

1. syntax-checks the replacement shell scripts;
2. creates a root-only archive of the old `/opt/arch-workstation` under `/var/backups/arch-workstation`;
3. preserves `/etc/arch-installer/install.conf` and `/etc/arch-installer/install.env`;
4. stages the new tree before replacing the installed tree;
5. repairs executable modes and `/usr/local/bin/archctl`;
6. appends the reduced-prompt migration defaults:
   - `AUR_HELPER_PACKAGE="paru-bin"`;
   - `AUR_NONINTERACTIVE=true`;
   - `PROVISION_NONINTERACTIVE=true`.

To retain manual AUR review prompts:

```bash
./upgrade-existing.sh --keep-interactive-aur
```

## Converge the installed system

Run as the normal user:

```bash
archctl finish
```

An accidental `sudo archctl finish` is automatically re-executed as the invoking user.

A 0.1 installation does not have the new state markers, so the first 0.2 run may repeat provisioning. The roles and package commands are idempotent. It will then inspect the existing Secure Boot and TPM state, repair/sign any EFI files that are not tracked, and stop only if a firmware action is genuinely required.

Check the result:

```bash
archctl status
archctl verify
sudo sbctl verify
```

## Roll back only the automation

The upgrader prints the backup path. To restore it, use a root shell and replace `/opt/arch-workstation` from that archive. This rolls back scripts and documentation only; it does not undo package transactions or security changes applied after the upgrade.
