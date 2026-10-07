#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/official-packages.sh"
[[ $# == 1 ]] || { echo 'Usage: package-list.sh ROLE' >&2; exit 2; }
official_role_packages "$1"
