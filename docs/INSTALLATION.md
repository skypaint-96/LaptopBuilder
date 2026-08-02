# Installation guide

This guide describes the version 0.2 fresh-install flow. The installer is destructive and supports a single x86-64 UEFI disk only.

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

## 2. Boot and connect the Arch ISO

Boot the official Arch ISO in UEFI mode. Confirm:

```bash
uname -m
ls /sys/firmware/efi/efivars >/dev/null
```

For Ethernet, NetworkManager usually connects automatically. For Wi-Fi:

```bash
nmcli device wifi list
nmcli device wifi connect "SSID" --ask
```

Check connectivity and time:

```bash
ping -c 3 archlinux.org
timedatectl status
```

## 3. Obtain the repository

```bash
pacman -Sy --needed git

git clone <repository-url> arch-t480-workstation
cd arch-t480-workstation
```

A release archive is also valid. Verify its checksum before extracting it.

## 4. Identify the whole target disk

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS
```

The default is `/dev/nvme0n1`. Never infer the correct device only from its position in the output.

## 5. Review configuration

```bash
cp config/install.conf.example config/install.conf
vim config/install.conf
```

The default T480 policy includes:

```bash
DISK="/dev/nvme0n1"
HOSTNAME="arch-t480"
USERNAME="mason"
CPU_VENDOR="intel"
GPU_VENDOR="intel"
ENABLE_T480=true
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
```

`AUR_NONINTERACTIVE=true` suppresses Paru review/rebuild prompts for only the explicit `AUR_PACKAGES` allow-list. Set it to `false` when manual inspection is preferred.

## 6. Supply secrets

The normal flow prompts twice for both the LUKS passphrase and user password before disk changes. The values remain shell variables and are not written to the repository.

For unattended lab use, root-readable files can be configured:

```bash
LUKS_PASSPHRASE_FILE="/root/luks.secret"
USER_PASSWORD_FILE="/root/user.secret"
```

Each file must be mode `0400` or `0600`; only the first line is read. Do not store them on the installed disk or commit them.

## 7. Run the non-destructive preflight

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

## 8. Install

```bash
./start.sh --reboot-firmware
```

`--reboot-firmware` requests firmware setup immediately after a successful install; omit it when you prefer to reboot manually. `start.sh` calls the root installer with `config/install.conf`. The installer asks for the two credentials and then requires the exact phrase:

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

## 9. Enable Secure Boot

When installation succeeds, reboot to firmware setup. Enable Secure Boot without clearing keys and without restoring factory keys. Remove the installation USB and boot the installed system.

The first unlock uses the long LUKS passphrase because TPM enrolment is deliberately deferred until the machine has actually booted the signed chain with Secure Boot active.

## 10. Finish first boot

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
- ask for the retained LUKS passphrase and a new TPM PIN;
- enrol the TPM2 token and rebuild the signed UKIs;
- run `archctl verify` and mark setup complete.

Choose a daily TPM PIN with enough digits to resist casual guessing. The normal LUKS passphrase remains installed and should be kept offline as the main recovery path.

## 11. Verify and test a reboot

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

## 12. Optional separate recovery key

The retained passphrase is already a fallback. An additional machine-generated recovery key can be added with:

```bash
archctl recovery-key
```

It is printed once. Store it offline and test it before depending on it.

## 13. Routine updates

```bash
archctl update
```

This opens one sudo session, upgrades official packages, updates configured AUR packages, rebuilds UKIs, ensures the fallback and systemd-boot loaders exist, signs/registers all EFI executables, and verifies the resulting chain.

Always read current Arch Linux news before a major upgrade.

## 14. Unattended disk installation

For controlled lab automation only:

```bash
NONINTERACTIVE=true
WIPE_CONFIRMATION="ERASE /dev/nvme0n1"
LUKS_PASSPHRASE_FILE="/root/luks.secret"
USER_PASSWORD_FILE="/root/user.secret"
```

Then run:

```bash
./start.sh
```

Firmware actions and TPM PIN creation cannot safely be made fully unattended by this repository.
