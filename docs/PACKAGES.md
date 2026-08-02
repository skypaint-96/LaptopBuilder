# Package inventory

This is the intended package policy rather than a version lock. Arch is rolling release, so exact versions are resolved at installation and update time.

## Base system and boot

Installed from official repositories during the ISO stage:

```text
base base-devel
linux linux-lts linux-firmware wireless-regdb
intel-ucode sof-firmware                 # default Intel profile
btrfs-progs cryptsetup dosfstools gptfdisk efibootmgr
mkinitcpio systemd-ukify sbsigntools sbctl tpm2-tools tpm2-tss
networkmanager wpa_supplicant openssh
sudo git vim curl rsync tar ansible-core python
man-db man-pages texinfo bash-completion zram-generator
```

The AMD CPU profile substitutes `amd-ucode` for Intel microcode/firmware choices.

## Xfce/X11 desktop

```text
xorg-server xorg-xinit xf86-input-libinput
xfce4-session xfce4-panel xfdesktop xfwm4 xfce4-settings xfce4-appfinder
xfce4-terminal xfce4-power-manager xfce4-notifyd xfce4-screensaver
xfce4-pulseaudio-plugin thunar thunar-volman tumbler
lightdm lightdm-gtk-greeter
pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
bluez bluez-utils
gnome-keyring polkit-gnome
gvfs gvfs-mtp udisks2 network-manager-applet
xdg-user-dirs xdg-utils xdg-desktop-portal-gtk
noto-fonts noto-fonts-emoji ttf-dejavu
```

The desktop Ansible role ensures these integration tools remain present:

```text
file-roller gnome-keyring mousepad polkit-gnome ristretto
xdg-desktop-portal xdg-desktop-portal-gtk
```

## Graphics profiles

Intel:

```text
mesa vulkan-intel intel-media-driver
```

AMD:

```text
mesa vulkan-radeon libva-mesa-driver
```

Generic:

```text
mesa
```

## Common command-line tools

```text
bash-completion bat btop curl fd fastfetch fzf git jq less
man-db man-pages pacman-contrib ripgrep rsync tar unzip vim wget zip
```

## Development

```text
ansible-core base-devel cmake dotnet-sdk git ninja shellcheck vim
```

## Docker

```text
docker docker-buildx docker-compose
```

## Gaming

Common:

```text
gamemode lib32-gamemode lib32-libpulse lib32-mesa
mangohud steam vulkan-tools
```

Intel adds:

```text
vulkan-intel lib32-vulkan-intel
```

AMD adds:

```text
vulkan-radeon lib32-vulkan-radeon
```

Steam requires the multilib repository, enabled by default. The vendor-specific Vulkan packages are installed before Steam so pacman does not have to choose an ambiguous native or 32-bit virtual provider. Configuration validation rejects gaming with `GPU_VENDOR="generic"`.

## Snapshots

```text
snapper snap-pac
```

## ThinkPad T480

```text
bolt ethtool fwupd smartmontools thermald tlp tlp-rdw
```

## Requested AUR packages

```text
microsoft-edge-stable-bin
visual-studio-code-bin
powershell-bin
```

The default helper bootstrap uses `paru-bin`, so first boot downloads the prebuilt Paru release through its AUR PKGBUILD rather than compiling Paru and selecting a Rust provider. `AUR_NONINTERACTIVE=true` installs only the configured allow-list with routine review prompts suppressed. Set it to `false` to print and confirm the helper build and retain Paru's review workflow. These packages are not built or supported by Arch Linux itself.

CI derives official and AUR package names from the repository configuration. It resolves official packages in a current Arch container and checks AUR names through the metadata API. Those checks detect naming/repository drift, not malicious or defective package contents.

## Optional PowerShell modules

Disabled by default:

```text
posh-git
Terminal-Icons
```
