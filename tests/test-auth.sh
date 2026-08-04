#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Authentication state must remain local to the installed user. The project may
# detect a OneDrive token but must never copy it into Git, USB data, or templates.
grep -q 'gh auth login --hostname github.com --web' "$ROOT/scripts/auth.sh"
grep -q 'gh auth setup-git --hostname github.com' "$ROOT/scripts/auth.sh"
grep -q 'onedrive --sync --verbose --dry-run' "$ROOT/scripts/auth.sh"
grep -q 'systemctl --user enable --now onedrive.service' "$ROOT/scripts/auth.sh"
grep -q 'rsync -a --ignore-existing' "$ROOT/scripts/auth.sh"
grep -q 'folder-backups' "$ROOT/scripts/auth.sh"
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
