# Security model

The repository combines encryption at rest, an owner-controlled verified boot chain, and TPM-assisted daily unlocking. Each layer has a separate purpose and recovery boundary.

## LUKS2 encryption at rest

The root Btrfs filesystem is inside LUKS2. Without a valid LUKS credential, removing the SSD or booting another operating system does not expose the filesystem contents.

The normal long passphrase is retained after TPM enrolment. Do not replace the only recovery credential with a very short numeric passphrase. The intended arrangement is:

1. TPM2 plus a daily PIN for routine boots;
2. the long LUKS passphrase for recovery;
3. optionally, a separately stored generated recovery key.

TPM enrolment adds a token; it does not delete ordinary passphrase slots. `tpm-remove` proves a non-TPM credential works before removing TPM tokens.

## Secure Boot owner keys

Fresh installation requires firmware Setup Mode before any disk changes. This moves the key-clear operation to the start of the process and lets the installer automatically:

- create owner PK, KEK, and db keys with `sbctl`;
- enrol them through UEFI variables;
- optionally include Microsoft certificates;
- install the systemd-boot normal and fallback loaders;
- build both configured UKIs;
- sign and record every `.efi` below `/efi/EFI`;
- fail installation if any discovered EFI executable does not verify.

The owner private keys remain under `/var/lib/sbctl/keys` on the encrypted root filesystem. Back them up to encrypted offline storage after the final system is working:

```bash
sudo tar -C /var/lib/sbctl -czf /path/to/encrypted-backup/sbctl-keys.tar.gz keys
```

Treat that archive as highly sensitive. Possession of the signing key permits signing code trusted by this firmware.

Do not restore factory keys after owner-key enrolment. The default `--microsoft` enrolment already includes Microsoft certificates alongside the owner keys for compatibility.

## Full EFI coverage

The original physical install exposed a gap where the fallback loader, systemd-boot, and both UKIs existed but were not all recorded in the `sbctl` database. Version 0.2 no longer assumes a fixed set of four paths. It discovers every `.efi` under `/efi/EFI`, runs `sbctl sign --save` for each, runs `sbctl sign-all`, and then requires `sbctl verify` to succeed.

This enforcement is used during installation, provisioning, explicit repair, TPM enrolment, and normal updates.

## TPM2 policy and PIN

TPM enrolment is only allowed after:

- Secure Boot is active in the running system;
- local owner signing keys exist;
- every EFI executable verifies;
- a TPM2 device is visible;
- the root volume is confirmed as LUKS2.

The default binds the token to PCR 7, which represents the Secure Boot policy, and requests a PIN. The PIN is not the LUKS passphrase; it authorises release of a high-entropy secret sealed to the TPM state. Repeated incorrect PIN attempts can trigger TPM dictionary-attack lockout.

Firmware resets, Secure Boot key changes, TPM clearing, motherboard replacement, or policy changes may invalidate TPM unlocking. Use the retained LUKS passphrase in that case and re-enrol deliberately.

## Secrets and automation boundaries

The repository never commits passwords, LUKS passphrases, TPM PINs, recovery keys, or Secure Boot private keys. Plaintext USB secret input must be a non-symlink file with mode `0400` or `0600` and is ignored by Git.

When requested, the builder collects every missing username/password/LUKS/TPM field before the long-running build, encrypts a JSON payload with GnuPG symmetric AES-256, and verifies the ciphertext before copying it. The bundle passphrase is not stored on the USB. The live launcher decrypts once into `/run`, which is RAM-backed, and gives the installer mode-0600 credential files. The ciphertext metadata contains only schema, time, and checksum, not the username.

The user password is consumed during installation and is never staged for first boot. The retained LUKS credential and TPM PIN may be staged temporarily in the encrypted `@credentials` Btrfs subvolume. This nested subvolume is excluded from normal root snapshots. `archctl finish` passes them to `systemd-cryptenroll` as transient systemd service credentials, verifies the TPM token, crypttab, rebuilt UKIs, and EFI signatures, then removes the files.

Without a USB credential bundle, the same values are collected together at live-install start and TPM enrolment falls back to an interactive prompt when staged credentials are unavailable. Physical firmware Setup Mode and Secure Boot enforcement remain explicit operator actions. Optional recovery-key capture also remains explicit.

## Live repository trust

The default USB workflow executes the configured live Git ref when it can be fetched. That makes the remote branch part of the installation supply chain. Use a repository you control, protect its branch, review changes, and prefer a credential-free HTTPS URL. Writable media metadata is parsed as an allow-listed base64 format and Git URLs/refs are validated before use, but these checks prevent command/option injection rather than authenticating remote content. The persistent Git bundle and embedded snapshot provide availability fallbacks, not cryptographic attestation of a compromised remote. A future high-assurance deployment should pin and independently verify a commit or signed tag.

## AUR policy

AUR packages execute community-maintained PKGBUILDs. Version 0.2 uses the prebuilt `paru-bin` AUR package to avoid compiling Paru and selecting a Rust provider.

The default `AUR_NONINTERACTIVE=true` suppresses routine PKGBUILD/rebuild prompts and acts only on this explicit allow-list:

```text
microsoft-edge-stable-bin
visual-studio-code-bin
powershell-bin
```

This is a conscious convenience/security trade-off. Set `AUR_NONINTERACTIVE=false` to print and confirm the helper PKGBUILD and retain Paru review prompts.

## Sudo and Ansible

The normal user authenticates once with `sudo -v`. A short-lived keepalive covers the provisioning run. Ansible is then invoked through `sudo env ... ansible-playbook` and the play itself uses `become: false`; this avoids an independent Ansible become-password prompt or non-interactive failure.

The sudo policy remains password-protected wheel access. No persistent NOPASSWD rule is created.

## Docker group

Membership in the `docker` group is effectively root-equivalent because the daemon can mount host paths and run privileged containers. Set `DOCKER_ADD_USER_TO_GROUP=false` to require `sudo docker` instead.

## SSH, TRIM, and snapshots

- The OpenSSH server is enabled by default when `ENABLE_SSH=true`. Review `/etc/ssh/sshd_config` and firewall/network exposure before using it outside a trusted network.
- Discard/TRIM through dm-crypt can reveal which encrypted blocks are unused. Set `ENABLE_SSD_TRIM=false` when that leakage matters more than SSD maintenance.
- Btrfs/Snapper snapshots share the same disk and encryption boundary. They are rollback points, not backups.

## Operational checks

After installation and after security-sensitive updates:

```bash
archctl verify
sudo sbctl status
sudo sbctl verify
systemctl --failed
```

Use `archctl update` rather than running a package upgrade and forgetting to revalidate the signed boot set.
