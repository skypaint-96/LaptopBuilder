#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_runtime_security
require_commands systemd-cryptenroll
luks_device=$(resolve_luks_device)

cat <<'EOF'
A high-entropy recovery key will be added to LUKS2 and printed once.
Store it offline, separately from this laptop. Do not save it in this repository.
EOF
systemd-cryptenroll --recovery-key "$luks_device"
success "Recovery key enrolled. Verify it from a controlled reboot before treating it as your only fallback."
