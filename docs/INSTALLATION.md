# Installation guide

This guide describes the version 0.3 fresh-install flow using the supported custom USB. See [USB.md](USB.md) for building and refreshing that media. The installer is destructive and supports a single x86-64 UEFI disk only.

## 1. Back up and prepare firmware

Back up every file on the target disk. For a ThinkPad T480, update BIOS and Thunderbolt firmware before replacing the existing operating system where practical.

Enter firmware setup with **F1** and configure:

| Setting | Required state |
|---|---|
| Boot mode | UEFI only |
| Legacy/CSM | Disabled |
| TPM/Security Chip | Enabled |
| Secure Boot enforcement | Disabled |
| Secure Boot key state | Keys cleared; Setup Mode enabled |

Clearing the keys before installation is intentional. It lets the installer enrol the new owner keys and sign the boot chain while the target is still mounted. Do not restore factory keys afterward. Microsoft certificates are included in the new trust store by default for firmware and option-ROM compatibility.

## 2. Build and boot the custom USB

From an installed Arch system, clone the repository and build the media:

```bash
git clone <repository-url> arch-workstation
cd arch-workstation
./build-usb.sh --device /dev/sdX --configure
```

Optionally use `--include-secrets --secure-file config/usb-secrets.json` as described in [USB.md](USB.md). Boot the resulting USB in UEFI mode. The `archws` menu starts automatically; option 1 is the normal live-source installation and refreshes the persistent offline caches before proceeding.

For Wi-Fi, open a shell from the menu and use NetworkManager if the online check cannot connect:

```bash
nmcli device wifi list
nmcli device wifi connect "SSID" --ask
archws
```

The live launcher selects the current remote project ref when available, then the persistent Git bundle, then the repository embedded in the ISO.

## 3. Select or update configuration

Use menu option 4 to edit the persistent installation configuration. The build-time guided configuration may already have set it. The normal T480 target is `/dev/nvme0n1`, but confirm this from model and serial number rather than assuming.

The normal defaults are equivalent to:

```bash
DISK="/dev/nvme0n1"
HOSTNAME="arch-t480"
USERNAME="mason"
KEYMAP="uk"
X11_LAYOUT="gb"
CPU_VENDOR="intel"
GPU_VENDOR="intel"
ENABLE_T480=true
ENABLE_SSH=true
ENABLE_MULTILIB=true
AUR_HELPER_PACKAGE="paru-bin"
AUR_NONINTERACTIVE=true
PROVISION_NONINTERACTIVE=true
ENABLE_SECURE_BOOT=true
REQUIRE_SETUP_MODE_AT_INSTALL=true
AUTO_PREPARE_SECURE_BOOT=true
ENABLE_TPM=true
TPM_PCRS="7"
TPM_WITH_PIN=true
TPM_PIN_MIN_LENGTH=6
```

`AUR_NONINTERACTIVE=true` suppresses Paru review/rebuild prompts only for the explicit `AUR_PACKAGES` allow-list. Set it to `false` when manual inspection is preferred.

## 4. Identify the whole target disk

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS
```

The default is `/dev/nvme0n1`. Never infer the correct device only from its position in the output.

## 5. Supply secrets

Without an encrypted USB bundle, the live launcher prompts for username, account password, LUKS passphrase, and TPM PIN together before cache refresh or disk changes. The values remain shell variables and are not written to the repository.

For direct installer use outside the launcher, root-readable files can be configured:

```bash
LUKS_PASSPHRASE_FILE="/root/luks.secret"
USER_PASSWORD_FILE="/root/user.secret"
TPM_PIN_FILE="/root/tpm-pin.secret"
```

Each file must be mode `0400` or `0600`; only the first line is read. Do not store them on the installed disk or commit them.

## 6. Run the non-destructive preflight

```bash
./start.sh preflight
```

The preflight verifies:

- x86-64 and UEFI boot;
- official Arch ISO unless explicitly overridden;
- whole-disk target with no mounts or active swap;
- Secure Boot disabled and Setup Mode enabled;
- TPM visibility when required;
- network and time service;
- live-ISO `multilib` activation and database synchronisation;
- resolution of every configured official package;
- exact AUR metadata matches for `paru-bin`, Edge, VS Code, and PowerShell.

Resolve every error before installation. No disk-erasure confirmation is requested in preflight mode.

## 7. Install

```bash
./start.sh --reboot-firmware
```

`--reboot-firmware` requests firmware setup immediately after a successful install; omit it when you prefer to reboot manually. The live launcher has already collected the username, account password, LUKS passphrase, and TPM PIN together. The destructive installer still requires the exact phrase:

```text
ERASE /dev/nvme0n1
```

It then:

1. creates GPT, EFI, and encrypted-root partitions;
2. formats and opens LUKS2;
3. creates Btrfs subvolumes and mounts them;
4. installs the base/Xfce system;
5. writes the single installed policy file at `/etc/arch-installer/install.conf`;
6. configures systemd-boot and both UKIs;
7. creates/enrols `sbctl` owner keys while firmware is in Setup Mode;
8. retains Microsoft certificates when configured;
9. signs and records every `.efi` under `/efi/EFI`;
10. verifies the full signed set before declaring success.

The installed automation is `/opt/arch-workstation`; `/usr/local/bin/archctl` points to it.

## 8. Enable Secure Boot

When installation succeeds, reboot to firmware setup. Enable Secure Boot without clearing keys and without restoring factory keys. Remove the installation USB and boot the installed system.

The first unlock uses the long LUKS passphrase because TPM enrolment is deliberately deferred until the machine has actually booted the signed chain with Secure Boot active.

## 9. Finish first boot

Log in as the configured user and run:

```bash
archctl finish
```

Run it as the normal user. If it is accidentally prefixed with `sudo`, `archctl` drops back to the invoking user before continuing. It asks for the normal Linux user password once, keeps the sudo timestamp alive, and performs root/user work in the correct contexts.

The state machine can safely be rerun. Depending on detected state it will:

- apply the full Arch upgrade;
- run all Ansible roles as root through the established sudo session;
- bootstrap `paru-bin` without Rust/Cargo provider selection;
- install the explicit AUR allow-list without routine review prompts;
- configure VS Code and PowerShell as the normal user;
- rebuild/sign/verify all boot assets after package transactions;
- consume staged LUKS/TPM credentials automatically when supplied by the USB, or prompt when unavailable;
- enrol the TPM2 token and rebuild the signed UKIs;
- run `archctl verify` and mark setup complete.

Choose a daily TPM PIN with enough digits to resist casual guessing. The normal LUKS passphrase remains installed and should be kept offline as the main recovery path.

## 10. Verify and test a reboot

```bash
archctl status
archctl verify
sudo sbctl status
sudo sbctl verify
systemctl --failed
```

Reboot and confirm the TPM PIN unlocks the disk:

```bash
sudo reboot
```

After login, Docker group membership should also be active:

```bash
docker run --rm hello-world
```

## 11. Optional separate recovery key

The retained passphrase is already a fallback. An additional machine-generated recovery key can be added with:

```bash
archctl recovery-key
```

It is printed once. Store it offline and test it before depending on it.

## 12. Routine updates

```bash
archctl update
```

This opens one sudo session, upgrades official packages, updates configured AUR packages, rebuilds UKIs, ensures the fallback and systemd-boot loaders exist, signs/registers all EFI executables, and verifies the resulting chain.

Always read current Arch Linux news before a major upgrade.

## 13. Direct or unattended installer use

The custom USB menu is the supported normal route. For direct use from an ArchISO checkout, create `config/install.conf` first:

```bash
cp config/install.conf.example config/install.conf
vim config/install.conf
./start.sh preflight
```

For controlled lab automation only:

```bash
NONINTERACTIVE=true
WIPE_CONFIRMATION="ERASE /dev/nvme0n1"
LUKS_PASSPHRASE_FILE="/root/luks.secret"
USER_PASSWORD_FILE="/root/user.secret"
TPM_PIN_FILE="/root/tpm-pin.secret"
```

Then run:

```bash
./start.sh
```

Firmware actions and TPM enrolment can consume staged credentials, but the firmware trust-boundary actions remain manual.
