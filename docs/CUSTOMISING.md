# Customising the repository

## Configuration-first changes

Most machine and policy choices belong in `config/install.conf`, copied from the example. Keep the example safe and general; keep machine-specific values in the ignored local file or in a private branch.

Important switches include:

| Variable | Effect |
|---|---|
| `CPU_VENDOR` | Selects Intel or AMD microcode packages |
| `GPU_VENDOR` | Selects Intel, AMD, or generic Mesa userspace; gaming requires Intel or AMD |
| `KERNELS` | Space-separated kernel package names and UKIs |
| `ENABLE_SSD_TRIM` | Controls dm-crypt discard and `fstrim.timer` |
| `ENABLE_AUR` | Enables the AUR helper and allow-list stage |
| `AUR_PACKAGES` | Space-separated AUR package allow-list |
| `ENABLE_DOCKER` | Installs and enables Docker |
| `DOCKER_ADD_USER_TO_GROUP` | Adds root-equivalent daemon access for the user |
| `ENABLE_GAMING` | Installs Steam and 32-bit graphics userspace |
| `ENABLE_SNAPSHOTS` | Installs Snapper and pacman snapshots |
| `ENABLE_T480` | Applies laptop-specific TLP, thermal, firmware, and SMART roles |
| `ENABLE_SSH` | Enables the OpenSSH server; false by default |
| `TPM_PCRS` | Selects the systemd TPM PCR binding |
| `TPM_WITH_PIN` | Requires a TPM PIN at early boot |

Configuration values are Bash assignments. Quote strings, use `true` or `false` for booleans, and do not add literal passwords.

## Using another x86-64 machine

For a generic Intel laptop or desktop:

```bash
CPU_VENDOR="intel"
GPU_VENDOR="intel"
ENABLE_T480=false
```

For an AMD CPU and AMD graphics machine:

```bash
CPU_VENDOR="amd"
GPU_VENDOR="amd"
ENABLE_T480=false
```

For graphics not explicitly modelled by the repository:

```bash
GPU_VENDOR="generic"
ENABLE_GAMING=false
```

The generic profile installs Mesa but no vendor-specific Vulkan or 32-bit Vulkan package. Validation rejects this profile when gaming is enabled because Steam needs an explicit 32-bit Vulkan provider. NVIDIA proprietary and hybrid-graphics designs need a dedicated role, initramfs module policy, signing review, and power-management testing before they should be treated as supported.

## Adding official packages

Put packages into the most relevant role under `ansible/roles/*/tasks/main.yml`. The existing roles use:

```yaml
- name: Install example package set
  ansible.builtin.command:
    argv:
      - pacman
      - --sync
      - --needed
      - --noconfirm
      - package-one
      - package-two
```

`--needed` makes repeat runs safe. The command tasks avoid requiring the much larger `community.general` collection solely for its pacman module.

Add every new official package name to `tests/check-arch-packages.sh`, then run:

```bash
make test
```

before committing. CI resolves the official package list in a current disposable Arch container.

## Adding a new role

Create:

```text
ansible/roles/ROLE_NAME/tasks/main.yml
```

Add the role to `ansible/site.yml` with a tag and a boolean guard when optional. Pass the setting from `scripts/provision.sh`, define a default in `ansible/group_vars/all.yml`, and validate the matching Bash configuration variable.

Roles should:

- use official packages when available;
- be safe on repeated runs;
- avoid changing unrelated user state;
- use handlers for service restarts;
- document security-sensitive group membership or exposed services.

## AUR packages

Add only reviewed package names to:

```bash
AUR_PACKAGES="existing-package new-package"
```

Do not add AUR helpers or arbitrary curl-to-shell commands to Ansible roles. Keep builds in the non-root AUR stage. The default `AUR_NONINTERACTIVE=true` suppresses routine Paru review prompts for the explicit allow-list; set it to `false` when you want the helper PKGBUILD printed and each AUR transaction reviewed interactively. CI derives expected names from the configuration and checks them through the AUR metadata API; metadata resolution is not a security review.

## Dotfiles

Managed defaults live under `dotfiles/` and are copied by the common role:

- `dotfiles/vimrc` -> `~/.vimrc`
- `dotfiles/gitconfig` -> `~/.gitconfig`

Git identity belongs in `~/.gitconfig.local`, which is included by the managed file but never populated by the repository.

The PowerShell profile is a loader under `~/.config/powershell/` that imports the versioned `powershell/profile.ps1`. Personal, unversioned overrides belong in:

```text
~/.config/powershell/profile.local.ps1
```

## PowerShell modules

Optional module names are listed in `powershell/modules.txt`. Installation is disabled by default because PSGallery modules add another supply chain. Enable explicitly:

```bash
INSTALL_POWERSHELL_MODULES=true
```

The configuration script installs missing modules for the current user only.

## VS Code

Settings and extension IDs live in `vscode/`. The provisioning stage calls the `code` CLI after the AUR package has been installed. Extensions are installed by publisher-qualified ID; review publisher ownership and extension updates separately.

## Desktop changes

Version 0.2 supports Xfce on X11 only. Replacing it is more than a package-list change: update the base desktop packages, display manager session, portals, polkit agent, screen locking, power management, verification checks, and documentation together.

## Storage changes

The disk and filesystem scripts are intentionally narrow. Adding dual boot, a separate `/home` partition, RAID, LVM, hibernation, or non-Btrfs filesystems requires explicit migration and recovery design. Do not simply weaken validation and assume the existing mount, boot, snapshot, and crypttab logic remains correct.
