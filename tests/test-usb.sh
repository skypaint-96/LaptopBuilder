#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../usb/lib/usb-common.sh
source "$ROOT/usb/lib/usb-common.sh"

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
usb_root="$temp/usb"
layout="$usb_root/MASON-ARCH"
mkdir -p "$layout/config" "$layout/runtime" "$layout/cache/repository" "$layout/state"
printf '%s\n' "$USB_LAYOUT_VERSION" > "$layout/.layout-version"
cp "$ROOT/config/usb.conf.example" "$layout/config/usb.conf"
cp "$ROOT/profiles/t480.conf" "$layout/config/install.conf"
mkdir -p "$usb_root/EFI/BOOT" "$usb_root/boot/grub"
printf loader > "$usb_root/EFI/BOOT/BOOTX64.EFI"
cp "$ROOT/usb/grub/grub.cfg" "$usb_root/boot/grub/grub.cfg"

for slot in a b; do
  mkdir -p "$usb_root/arch-$slot/boot/x86_64" "$usb_root/arch-$slot/x86_64"
  printf 'test-%s\n' "$slot" > "$usb_root/arch-$slot/version"
  printf kernel > "$usb_root/arch-$slot/boot/x86_64/vmlinuz-linux"
  printf initramfs > "$usb_root/arch-$slot/boot/x86_64/initramfs-linux.img"
  printf squashfs > "$usb_root/arch-$slot/x86_64/airootfs.sfs"
  printf signature > "$usb_root/arch-$slot/x86_64/airootfs.sfs.cms.sig"
done

repo_tree="$temp/repo"
while IFS= read -r required; do
  mkdir -p "$repo_tree/$(dirname -- "$required")"
  printf '# synthetic test file: %s\n' "$required" > "$repo_tree/$required"
done < <(usb_repository_required_paths)
tar -C "$repo_tree" -czf "$layout/cache/repository/current.tar.gz" .
printf '%s  current.tar.gz\n' "$(sha256sum "$layout/cache/repository/current.tar.gz" | awk '{print $1}')" \
  > "$layout/cache/repository/current.sha256"
cp "$layout/cache/repository/current.tar.gz" "$layout/cache/repository/previous.tar.gz"
printf '%s  previous.tar.gz\n' "$(sha256sum "$layout/cache/repository/previous.tar.gz" | awk '{print $1}')" \
  > "$layout/cache/repository/previous.sha256"

usb_verify_layout "$usb_root"
usb_verify_arch_slot "$usb_root" a
usb_verify_arch_slot "$usb_root" b
[[ $(usb_github_repository_slug https://github.com/example/workstation.git) == example/workstation ]]
[[ $(usb_urlencode 'feature/usb test') == feature%2Fusb%20test ]]

# Simulate power loss between the Arch slot rename steps. A complete old slot
# is preferred over an uncommitted new slot; a lone complete new slot is then
# completed on the next recovery pass.
mv "$usb_root/arch-a" "$usb_root/arch-a.old"
cp -a "$usb_root/arch-b" "$usb_root/arch-a.new"
usb_recover_interrupted_updates "$usb_root"
[[ $(<"$usb_root/arch-a/version") == test-a ]]
[[ ! -e $usb_root/arch-a.old && ! -e $usb_root/arch-a.new ]]
mv "$usb_root/arch-a" "$usb_root/arch-a.new"
usb_recover_interrupted_updates "$usb_root"
usb_verify_arch_slot "$usb_root" a

# Simulate interruption after the old package-cache pair was renamed but
# before the new pair was activated.
for cache in pacman aur; do
  mkdir -p "$layout/cache/$cache.old"
done
printf package-db > "$layout/cache/pacman.old/workstation.db"
printf aur-db > "$layout/cache/aur.old/workstation-aur.db"
for cache in pacman aur; do
  (
    cd "$layout/cache/$cache.old"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' \
      | LC_ALL=C sort | xargs -r sha256sum > SHA256SUMS
  )
done
usb_recover_interrupted_updates "$usb_root"
usb_verify_directory_manifest "$layout/cache/pacman"
usb_verify_directory_manifest "$layout/cache/aur"
[[ ! -e $layout/cache/pacman.old && ! -e $layout/cache/aur.old ]]

usb_write_active_slot "$usb_root" b
[[ $(usb_read_active_slot "$usb_root") == b ]]
[[ $(usb_other_slot b) == a ]]
usb_verify_sha_file "$layout/cache/repository/current.tar.gz" "$layout/cache/repository/current.sha256"

bad="$temp/bad-usb.conf"
cp "$ROOT/config/usb.conf.example" "$bad"
printf '\nREPO_URL="https://example.com/not-github"\n' >> "$bad"
if (usb_load_config "$bad") >/dev/null 2>&1; then
  echo 'Non-GitHub repository URL unexpectedly passed USB config validation.' >&2
  exit 1
fi

# Corrupt current after creating previous to prove the verifier retains a
# working repository fallback.
printf corruption >> "$layout/cache/repository/current.tar.gz"
bash "$ROOT/usb/verify-usb.sh" --usb-root "$usb_root" >/dev/null

printf corruption >> "$layout/cache/repository/previous.tar.gz"
if bash "$ROOT/usb/verify-usb.sh" --usb-root "$usb_root" >/dev/null 2>&1; then
  echo 'USB verification unexpectedly accepted two damaged repository generations.' >&2
  exit 1
fi

grep -q 'archisobasedir=arch-a' "$ROOT/usb/grub/grub.cfg"
grep -q 'archisobasedir=arch-b' "$ROOT/usb/grub/grub.cfg"
grep -q 'previous.tar.gz' "$ROOT/usb/start.sh"
grep -q 'inactive slot' "$ROOT/usb/refresh-arch.sh"
grep -q 'ERASE \$DISK' "$ROOT/usb/create-usb.sh"

echo 'USB layout, fallback, and validation tests passed.'
