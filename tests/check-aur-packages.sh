#!/usr/bin/env bash
set -Eeuo pipefail

command -v curl >/dev/null 2>&1 || {
  echo 'curl is required for AUR metadata validation.' >&2
  exit 1
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/packages.sh
source "$ROOT/scripts/lib/packages.sh"

load_config "$ROOT/config/install.conf.example"
collect_aur_packages packages

curl_args=(
  --fail
  --silent
  --show-error
  --retry 3
  --get
)
for package in "${packages[@]}"; do
  curl_args+=(--data-urlencode "arg[]=$package")
done

response=$(curl "${curl_args[@]}" https://aur.archlinux.org/rpc/v5/info)
for package in "${packages[@]}"; do
  if ! grep -Eq '"Name"[[:space:]]*:[[:space:]]*"'"$package"'"' <<< "$response"; then
    echo "AUR package did not resolve exactly: $package" >&2
    exit 1
  fi
done

echo "AUR metadata resolution passed for ${#packages[@]} package(s)."
