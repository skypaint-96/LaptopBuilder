#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Invoke through Bash so a checkout made on FAT/NTFS or committed with lost
# executable metadata can still start and repair the rest of the project tree.
exec bash "$ROOT/usb/build.sh" "$@"
