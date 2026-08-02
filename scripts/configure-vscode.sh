#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
require_non_root
require_commands code curl

settings_dir="$HOME/.config/Code/User"
install -d -m 0755 "$settings_dir"
install -m 0644 "$REPO_ROOT/vscode/settings.json" "$settings_dir/settings.json"

if ! curl --connect-timeout 5 --max-time 15 -fsS https://marketplace.visualstudio.com/ -o /dev/null 2>/dev/null; then
  warn "VS Code settings were applied, but extension installation was skipped while offline."
  exit 0
fi

while IFS= read -r extension; do
  [[ -n $extension && $extension != \#* ]] || continue
  info "Ensuring VS Code extension is installed: $extension"
  code --install-extension "$extension" >/dev/null
done < "$REPO_ROOT/vscode/extensions.txt"

success "VS Code settings and extensions applied."
