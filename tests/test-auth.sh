#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Authentication state must remain local to the installed user. The project may
# detect a OneDrive token but must never copy it into Git, USB data, or templates.
grep -q 'gh auth login --hostname github.com --web' "$ROOT/scripts/auth.sh"
grep -q 'gh auth setup-git --hostname github.com' "$ROOT/scripts/auth.sh"
grep -q 'systemctl --user start --no-block' "$ROOT/scripts/auth.sh"
grep -q 'prepare_edge_for_oauth' "$ROOT/scripts/auth.sh"
grep -q 'onedrive --confdir="\$ONEDRIVE_CONFIG_DIR" --sync --verbose' "$ROOT/scripts/onedrive-bootstrap.sh"
grep -q 'configure_onedrive_links' "$ROOT/scripts/onedrive-bootstrap.sh"
grep -q 'systemctl --user enable --now "$service_name"' "$ROOT/scripts/onedrive-bootstrap.sh"
grep -q 'rsync -a --ignore-existing' "$ROOT/scripts/lib/onedrive.sh"
grep -q 'folder-backups' "$ROOT/scripts/lib/onedrive.sh"
grep -q 'ExecStart=/usr/local/bin/arch-workstation-onedrive-bootstrap' "$ROOT/ansible/roles/cloud/templates/arch-workstation-onedrive-bootstrap.service.j2"
grep -q 'notify-send' "$ROOT/scripts/lib/onedrive.sh"
grep -q '/var/lib/arch-workstation/complete' "$ROOT/scripts/first-login-auth.sh"
grep -q 'first-login-complete' "$ROOT/scripts/first-login-auth.sh"
grep -q 'skip_dotfiles' "$ROOT/ansible/roles/cloud/templates/onedrive-config.j2"
grep -q 'skip_symlinks' "$ROOT/ansible/roles/cloud/templates/onedrive-config.j2"
grep -q 'use_recycle_bin' "$ROOT/ansible/roles/cloud/templates/onedrive-config.j2"

if grep -R "cp .*refresh_token\|rsync .*refresh_token\|tar .*refresh_token" \
  "$ROOT/scripts" "$ROOT/usb" "$ROOT/ansible" >/dev/null 2>&1; then
  echo 'OneDrive token-copy logic must not be added to the project.' >&2
  exit 1
fi

echo 'Authentication and OneDrive safety assertions passed.'

# Exercise the safe local-folder migration without contacting OneDrive.
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT
(
  export HOME="$test_home/home"
  mkdir -p "$HOME/Documents" "$HOME/Pictures" "$HOME/Videos" "$HOME/OneDrive/Documents"
  printf 'local\n' > "$HOME/Documents/local.txt"
  printf 'remote\n' > "$HOME/OneDrive/Documents/collision.txt"
  printf 'local collision\n' > "$HOME/Documents/collision.txt"
  ONEDRIVE_SYNC_DIR=OneDrive
  ONEDRIVE_LINK_DIRS='Documents Pictures Videos'
  ONEDRIVE_NOTIFY_ON_COMPLETION=false
  # shellcheck source=../scripts/lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  # shellcheck source=../scripts/lib/onedrive.sh
  source "$ROOT/scripts/lib/onedrive.sh"
  initialise_onedrive_state
  configure_onedrive_links
  [[ -L $HOME/Documents && -L $HOME/Pictures && -L $HOME/Videos ]]
  [[ $(cat "$HOME/OneDrive/Documents/local.txt") == local ]]
  [[ $(cat "$HOME/OneDrive/Documents/collision.txt") == remote ]]
  find "$HOME/.local/share/arch-workstation/folder-backups" -path '*/Documents/collision.txt' -print -quit | grep -q .
)
