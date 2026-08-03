#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT

mkdir "$TEMP/source"
git -C "$TEMP/source" init -q -b main
git -C "$TEMP/source" config user.name 'Cache Test'
git -C "$TEMP/source" config user.email 'cache-test@example.invalid'
mkdir -p "$TEMP/source/usb"
cp "$ROOT/usb/API_VERSION" "$TEMP/source/usb/API_VERSION"
printf '%s\n' 'offline repository probe' > "$TEMP/source/probe.txt"
git -C "$TEMP/source" add probe.txt usb/API_VERSION
git -C "$TEMP/source" commit -qm 'Create cache probe'
cp "$ROOT/config/install.conf.example" "$TEMP/install.conf"

run=("$ROOT/usb/cache.sh")
if [[ $(id -u) -ne 0 ]]; then
  if sudo -n true >/dev/null 2>&1; then
    run=(sudo -n "$ROOT/usb/cache.sh")
  else
    echo 'USB repository-cache test skipped because root privilege is unavailable.' >&2
    exit 0
  fi
fi

"${run[@]}" \
  --cache-root "$TEMP/cache" \
  --config "$TEMP/install.conf" \
  --source-repo "$TEMP/source" \
  --repo-ref main \
  --repo-only

git bundle verify "$TEMP/cache/repo/project.bundle" >/dev/null 2>&1 \
  || git --git-dir="$TEMP/cache/repo/mirror.git" bundle verify "$TEMP/cache/repo/project.bundle" >/dev/null
git clone -q "$TEMP/cache/repo/project.bundle" "$TEMP/clone"
grep -qx 'offline repository probe' "$TEMP/clone/probe.txt"
grep -q '^ARCHWS_REPO_REF=main$' "$TEMP/cache/repo/repository.env"

# A staged-but-uncommitted change must be snapshotted rather than silently
# caching the old HEAD. This is important while developing/testing a USB build.
printf '%s\n' 'staged repository probe' > "$TEMP/source/probe.txt"
git -C "$TEMP/source" add probe.txt
"${run[@]}" \
  --cache-root "$TEMP/staged-cache" \
  --config "$TEMP/install.conf" \
  --source-repo "$TEMP/source" \
  --repo-ref main \
  --repo-only
git clone -q "$TEMP/staged-cache/repo/project.bundle" "$TEMP/staged-clone"
grep -qx 'staged repository probe' "$TEMP/staged-clone/probe.txt"

mkdir "$TEMP/source-archive"
cp -a "$TEMP/source/probe.txt" "$TEMP/source/usb" "$TEMP/source-archive/"
"${run[@]}" \
  --cache-root "$TEMP/archive-cache" \
  --config "$TEMP/install.conf" \
  --source-repo "$TEMP/source-archive" \
  --repo-ref main \
  --repo-only
git clone -q "$TEMP/archive-cache/repo/project.bundle" "$TEMP/archive-clone"
grep -qx 'staged repository probe' "$TEMP/archive-clone/probe.txt"

echo 'Persistent project-cache tests passed.'
