#!/usr/bin/env bash
# Canonical official package roots. Keep role selection in ansible/site.yml and
# profile selection in build_package_lists; this file only owns package names.

OFFICIAL_BASE_PACKAGES=(
  base base-devel archlinux-keyring linux-firmware wireless-regdb
  btrfs-progs cryptsetup dosfstools gptfdisk efibootmgr
  mkinitcpio systemd-ukify sbsigntools sbctl tpm2-tools tpm2-tss
  networkmanager wpa_supplicant openssh
  sudo git vim curl rsync tar ansible-core python
  man-db man-pages texinfo bash-completion zram-generator
  xorg-server xorg-xinit xf86-input-libinput
  xfce4-session xfce4-panel xfdesktop xfwm4 xfce4-settings xfce4-appfinder
  xfce4-terminal xfce4-power-manager xfce4-notifyd xfce4-screensaver
  xfce4-pulseaudio-plugin thunar thunar-volman tumbler
  lightdm lightdm-gtk-greeter
  pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
  bluez bluez-utils gnome-keyring polkit-gnome
  gvfs gvfs-mtp udisks2 network-manager-applet
  xdg-user-dirs xdg-utils xdg-desktop-portal-gtk
  noto-fonts noto-fonts-emoji ttf-dejavu
)
OFFICIAL_CPU_INTEL=(intel-ucode sof-firmware)
OFFICIAL_CPU_AMD=(amd-ucode)
OFFICIAL_GPU_INTEL=(mesa vulkan-intel intel-media-driver)
OFFICIAL_GPU_AMD=(mesa vulkan-radeon libva-mesa-driver)
OFFICIAL_GPU_GENERIC=(mesa)

OFFICIAL_COMMON=(
  bash-completion bat btop curl fd fastfetch fzf git github-cli jq less
  man-db man-pages openssh pacman-contrib ripgrep rsync tar unzip vim wget zip
)
OFFICIAL_DESKTOP=(
  bluez bluez-utils blueman file-roller gnome-keyring libnotify mousepad mpv
  polkit-gnome ristretto xdg-desktop-portal xdg-desktop-portal-gtk
)
OFFICIAL_DEVELOPMENT=(ansible-core base-devel cmake dotnet-sdk git ninja shellcheck vim)
OFFICIAL_DOCKER=(docker docker-buildx docker-compose)
OFFICIAL_GAMING=(gamemode lib32-gamemode lib32-libpulse lib32-mesa mangohud steam vulkan-tools)
OFFICIAL_GAMING_INTEL=(lib32-vulkan-intel vulkan-intel)
OFFICIAL_GAMING_AMD=(lib32-vulkan-radeon vulkan-radeon)
OFFICIAL_SNAPSHOTS=(snap-pac snapper)
OFFICIAL_T480=(bolt ethtool fwupd smartmontools thermald tlp tlp-rdw)

official_role_packages() {
  case $1 in
    common) printf '%s\n' "${OFFICIAL_COMMON[@]}" ;;
    desktop) printf '%s\n' "${OFFICIAL_DESKTOP[@]}" ;;
    development) printf '%s\n' "${OFFICIAL_DEVELOPMENT[@]}" ;;
    docker) printf '%s\n' "${OFFICIAL_DOCKER[@]}" ;;
    gaming) printf '%s\n' "${OFFICIAL_GAMING[@]}" ;;
    gaming-intel) printf '%s\n' "${OFFICIAL_GAMING_INTEL[@]}" ;;
    gaming-amd) printf '%s\n' "${OFFICIAL_GAMING_AMD[@]}" ;;
    snapshots) printf '%s\n' "${OFFICIAL_SNAPSHOTS[@]}" ;;
    t480) printf '%s\n' "${OFFICIAL_T480[@]}" ;;
    *) printf 'Unknown official package group: %s\n' "$1" >&2; return 1 ;;
  esac
}
