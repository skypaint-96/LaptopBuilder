#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT

mkdir "$TEMP/source"
git -C "$TEMP/source" init -q -b main
git -C "$TEMP/source" config user.name 'Cache Test'
git -C "$TEMP/source" config user.email 'cache-test@example.invalid'
mkdir -p "$TEMP/source/usb/lib"
for path in start.sh install.sh archctl build-usb.sh; do
  cp "$ROOT/$path" "$TEMP/source/$path"
done
for path in cache.sh configure.sh secrets.sh; do
  cp "$ROOT/usb/$path" "$TEMP/source/usb/$path"
done
cp "$ROOT/usb/lib/common.sh" "$TEMP/source/usb/lib/common.sh"
cp "$ROOT/usb/API_VERSION" "$TEMP/source/usb/API_VERSION"
printf '%s\n' 'offline repository probe' > "$TEMP/source/probe.txt"
git -C "$TEMP/source" add probe.txt start.sh install.sh archctl build-usb.sh usb
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
[[ -x $TEMP/clone/start.sh && -x $TEMP/clone/usb/cache.sh ]]
[[ $(tr -d '[:space:]' < "$TEMP/clone/usb/API_VERSION") == 2 ]]
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
cp -a "$TEMP/source/probe.txt" "$TEMP/source/usb" \
  "$TEMP/source/start.sh" "$TEMP/source/install.sh" "$TEMP/source/archctl" \
  "$TEMP/source/build-usb.sh" "$TEMP/source-archive/"
"${run[@]}" \
  --cache-root "$TEMP/archive-cache" \
  --config "$TEMP/install.conf" \
  --source-repo "$TEMP/source-archive" \
  --repo-ref main \
  --repo-only
git clone -q "$TEMP/archive-cache/repo/project.bundle" "$TEMP/archive-clone"
grep -qx 'staged repository probe' "$TEMP/archive-clone/probe.txt"

echo 'Persistent project-cache tests passed.'
