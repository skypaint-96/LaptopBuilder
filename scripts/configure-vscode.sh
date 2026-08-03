#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
require_non_root
require_commands code

settings_dir="$HOME/.config/Code/User"
install -d -m 0755 "$settings_dir"
install -m 0644 "$REPO_ROOT/vscode/settings.json" "$settings_dir/settings.json"

while IFS= read -r extension; do
  [[ -n $extension && $extension != \#* ]] || continue
  info "Ensuring VS Code extension is installed: $extension"
  code --install-extension "$extension" --force >/dev/null
done < "$REPO_ROOT/vscode/extensions.txt"

success "VS Code settings and extensions applied."
