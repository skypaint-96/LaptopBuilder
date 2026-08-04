# Migrating an existing installation

Version 0.3 can replace the automation on a working 0.1 or 0.2 installation without reinstalling Arch or deliberately changing LUKS, Secure Boot, TPM, user data, or package state.

## Upgrade

Download and verify the 0.3 release, then extract it somewhere outside `/opt/arch-workstation`, for example in `~/Downloads`.

```bash
cd ~/Downloads/arch-t480-workstation
./upgrade-existing.sh
```

The script elevates itself and:

1. syntax-checks the replacement shell scripts;
2. creates a root-only archive of the old `/opt/arch-workstation` under `/var/backups/arch-workstation`;
3. preserves `/etc/arch-installer/install.conf` and `/etc/arch-installer/install.env`;
4. stages the new tree before replacing the installed tree;
5. repairs executable modes and the `/usr/local/bin/archctl`, `arch-workstation-start`, and `arch-workstation-build-usb` links;
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

After the first-boot workflow is complete, use `archctl apply` to reapply the desired configuration without rerunning the Secure Boot/TPM state machine. Existing `install.conf` values are preserved during migration; set `ENABLE_SSH=true` there when upgrading a machine that previously opted out.

An accidental `sudo archctl finish` is automatically re-executed as the invoking user.

An older installation may not have every current state marker, so the first 0.3 run may repeat provisioning. The roles and package commands are idempotent. It then inspects the existing Secure Boot and TPM state, repairs/signs any EFI files that are not tracked, and stops only if a firmware action is genuinely required.

The migration also installs the restored USB builder. It does not rewrite an existing USB automatically; build a new one with `arch-workstation-build-usb` or `./build-usb.sh` from the release checkout.

Check the result:

```bash
archctl status
archctl verify
sudo sbctl verify
```

## Roll back only the automation

The upgrader prints the backup path. To restore it, use a root shell and replace `/opt/arch-workstation` from that archive. This rolls back scripts and documentation only; it does not undo package transactions or security changes applied after the upgrade.
