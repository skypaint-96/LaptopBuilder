#!/usr/bin/env bash

# Package selection lives in one place so the live installer, offline cache
# builder, target installation, and package-resolution tests stay aligned.

append_packages() {
  local -n _target=$1
  shift
  _target+=("$@")
}

validate_package_name() {
  [[ $1 =~ ^[A-Za-z0-9@._+:-]+$ ]]
}

collect_official_packages() {
  local -n _packages=$1
  local -a kernels cpu_packages gpu_packages extra_packages
  local package
  _packages=()

  read -r -a kernels <<< "$KERNELS"
  read -r -a extra_packages <<< "${EXTRA_OFFICIAL_PACKAGES:-}"

  case "$CPU_VENDOR" in
    intel) cpu_packages=(intel-ucode sof-firmware) ;;
    amd) cpu_packages=(amd-ucode) ;;
  esac

  case "$GPU_VENDOR" in
    intel) gpu_packages=(mesa vulkan-intel intel-media-driver) ;;
    amd) gpu_packages=(mesa vulkan-radeon libva-mesa-driver) ;;
    generic) gpu_packages=(mesa) ;;
  esac

  append_packages _packages \
    base base-devel archlinux-keyring pacman "${kernels[@]}" linux-firmware wireless-regdb \
    "${cpu_packages[@]}" "${gpu_packages[@]}" \
    btrfs-progs cryptsetup dosfstools gptfdisk efibootmgr \
    mkinitcpio systemd-ukify sbsigntools sbctl tpm2-tools tpm2-tss \
    networkmanager wpa_supplicant openssh sudo git vim curl rsync tar ansible-core python \
    man-db man-pages texinfo bash-completion zram-generator \
    xorg-server xorg-xinit xf86-input-libinput \
    xfce4-session xfce4-panel xfdesktop xfwm4 xfce4-settings xfce4-appfinder \
    xfce4-terminal xfce4-power-manager xfce4-notifyd xfce4-screensaver \
    xfce4-pulseaudio-plugin thunar thunar-volman tumbler \
    lightdm lightdm-gtk-greeter \
    pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol \
    bluez bluez-utils gnome-keyring polkit-gnome \
    gvfs gvfs-mtp udisks2 network-manager-applet \
    xdg-user-dirs xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk \
    noto-fonts noto-fonts-emoji ttf-dejavu \
    bat btop fd fastfetch fzf jq less pacman-contrib ripgrep unzip wget zip \
    file-roller mousepad ristretto \
    cmake dotnet-sdk ninja shellcheck

  if bool_true "$ENABLE_DOCKER"; then
    append_packages _packages docker docker-buildx docker-compose
  fi

  if bool_true "$ENABLE_GAMING"; then
    case "$GPU_VENDOR" in
      intel) append_packages _packages lib32-vulkan-intel vulkan-intel ;;
      amd) append_packages _packages lib32-vulkan-radeon vulkan-radeon ;;
    esac
    append_packages _packages gamemode lib32-gamemode lib32-libpulse lib32-mesa mangohud steam vulkan-tools
  fi

  if bool_true "$ENABLE_SNAPSHOTS"; then
    append_packages _packages snap-pac snapper
  fi

  if bool_true "$ENABLE_T480"; then
    append_packages _packages bolt ethtool fwupd smartmontools thermald tlp tlp-rdw
  fi

  for package in "${extra_packages[@]}"; do
    validate_package_name "$package" || die "Invalid package name in EXTRA_OFFICIAL_PACKAGES: $package"
  done
  append_packages _packages "${extra_packages[@]}"

  # Sorting makes cache manifests deterministic and removes duplicates from
  # overlapping roles.
  mapfile -t _packages < <(printf '%s\n' "${_packages[@]}" | awk 'NF' | LC_ALL=C sort -u)
}

collect_aur_packages() {
  local -n _packages=$1
  local -a configured_packages
  local package
  _packages=()
  bool_true "$ENABLE_AUR" || return 0
  read -r -a configured_packages <<< "$AUR_PACKAGES"
  _packages=("$AUR_HELPER_PACKAGE" "${configured_packages[@]}")
  for package in "${_packages[@]}"; do
    validate_package_name "$package" || die "Invalid configured AUR package name: $package"
  done
  mapfile -t _packages < <(printf '%s\n' "${_packages[@]}" | awk 'NF' | LC_ALL=C sort -u)
}

collect_all_requested_packages() {
  local -n _packages=$1
  local -a official aur
  collect_official_packages official
  collect_aur_packages aur
  _packages=("${official[@]}" "${aur[@]}")
}
