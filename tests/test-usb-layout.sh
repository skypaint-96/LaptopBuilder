#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/config/install.conf.example" "$TEMP/install.conf"

"$ROOT/usb/configure.sh" --config "$TEMP/install.conf" \
  --set HOSTNAME=layout-test \
  --set USERNAME=layoutuser \
  --set TPM_PIN_MIN_LENGTH=6

# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$ROOT/scripts/lib/config.sh"
# shellcheck source=../usb/lib/common.sh
source "$ROOT/usb/lib/common.sh"
load_config "$TEMP/install.conf"
validate_config runtime
[[ $HOSTNAME == layout-test ]]
[[ $USERNAME == layoutuser ]]
[[ $TPM_PIN_MIN_LENGTH == 6 ]]

write_media_environment "$TEMP/media.env" \
  'https://example.invalid/mason/arch-workstation.git' 'main' '0.3.0' 'abc123'
unset ARCHWS_REPO_URL ARCHWS_REPO_REF ARCHWS_MEDIA_VERSION ARCHWS_BUILD_COMMIT
read_media_environment "$TEMP/media.env"
[[ $ARCHWS_REPO_URL == 'https://example.invalid/mason/arch-workstation.git' ]]
[[ $ARCHWS_REPO_REF == main ]]
[[ $ARCHWS_MEDIA_VERSION == 0.3.0 ]]
[[ $ARCHWS_BUILD_COMMIT == abc123 ]]
validate_git_repository_source 'https://example.invalid/mason/arch-workstation.git' main
validate_git_repository_source 'git@example.invalid:mason/arch-workstation.git' refs/tags/v0.3.0
if (validate_git_repository_source 'https://user:password@example.invalid/repo.git' main) >/dev/null 2>&1; then
  echo 'A Git URL containing inline credentials unexpectedly passed validation.' >&2
  exit 1
fi
if (validate_git_repository_source '--upload-pack=malicious' main) >/dev/null 2>&1; then
  echo 'An option-like Git URL unexpectedly passed validation.' >&2
  exit 1
fi
if (validate_git_repository_source 'https://example.invalid/repo.git' '-unsafe-ref') >/dev/null 2>&1; then
  echo 'An option-like Git ref unexpectedly passed validation.' >&2
  exit 1
fi
printf '%s\n' 'ARCHWS_REPO_URL=$(touch /tmp/archws-media-env-executed)' > "$TEMP/unsafe-media.env"
rm -f /tmp/archws-media-env-executed
if (read_media_environment "$TEMP/unsafe-media.env") >/dev/null 2>&1; then
  echo 'Unsafe media metadata unexpectedly passed validation.' >&2
  exit 1
fi
[[ ! -e /tmp/archws-media-env-executed ]]

mkdir -p "$TEMP/tracked-source/config" "$TEMP/tracked-copy"
git -C "$TEMP/tracked-source" init -q -b main
git -C "$TEMP/tracked-source" config user.name 'USB Layout Test'
git -C "$TEMP/tracked-source" config user.email 'usb-layout@example.invalid'
printf '%s\n' safe > "$TEMP/tracked-source/safe.txt"
printf '%s\n' plaintext-secret > "$TEMP/tracked-source/config/usb-secrets.json"
printf '%s\n' ciphertext > "$TEMP/tracked-source/stale.gpg"
git -C "$TEMP/tracked-source" add -f safe.txt config/usb-secrets.json stale.gpg
git -C "$TEMP/tracked-source" commit -qm 'Create tracked exclusion probes'
copy_tracked_repository "$TEMP/tracked-source" "$TEMP/tracked-copy"
[[ -r $TEMP/tracked-copy/safe.txt ]]
[[ ! -e $TEMP/tracked-copy/config/usb-secrets.json ]]
[[ ! -e $TEMP/tracked-copy/stale.gpg ]]

grep -q 'mkarchiso' "$ROOT/usb/build.sh"
grep -q 'sgdisk -N 0' "$ROOT/usb/build.sh"
grep -q 'cmp -n' "$ROOT/usb/build.sh"
grep -q 'ARCHWS_DATA' "$ROOT/usb/live/archws-live"
grep -q 'udevadm settle --timeout=10' "$ROOT/usb/live/archws-live"
grep -q 'for attempt in {1..12}' "$ROOT/usb/live/archws-live"
grep -q 'Install using live project and live Arch sources' "$ROOT/usb/live/archws-live"
grep -q 'Install using the offline project and official package cache' "$ROOT/usb/live/archws-live"
grep -q 'Refresh all offline caches without installing' "$ROOT/usb/live/archws-live"
grep -q '/usr/local/bin/archws' "$ROOT/usb/build.sh"
grep -q 'ARCHWS_LAUNCH_ATTEMPTED' "$ROOT/usb/build.sh"
grep -q 'project_is_compatible' "$ROOT/usb/live/archws-live"
grep -q 'Configure or check networking' "$ROOT/usb/live/archws-live"
grep -q 'set USERNAME=archuser' "$ROOT/usb/live/archws-live"
grep -q 'systemctl start iwd' "$ROOT/usb/live/archws-live"
grep -Fq 'if ! "$PROJECT_ROOT/usb/cache.sh"' "$ROOT/usb/live/archws-live"
grep -q 'validate_repository_metadata' "$ROOT/usb/live/archws-live"
! grep -qE 'source .*media\.env' "$ROOT/usb/live/archws-live"
grep -q 'Preserving the installation configuration already stored on the USB' "$ROOT/usb/build.sh"
grep -q 'Preserving the encrypted credential bundle currently stored on the USB' "$ROOT/usb/build.sh"
grep -q -- '--no-secrets would leave the placeholder username' "$ROOT/usb/build.sh"
grep -q -- '--refresh-only and --no-refresh-cache cannot be combined' "$ROOT/usb/build.sh"
grep -q -- '--iso-only cannot store installation secrets' "$ROOT/usb/build.sh"
grep -q 'Persistent media metadata is invalid; using the immutable metadata' "$ROOT/usb/live/archws-live"
grep -q 'diff --cached --quiet HEAD' "$ROOT/usb/cache.sh"
grep -q -- "--exclude='config/usb-secrets.json'" "$ROOT/scripts/install/20-base.sh"
[[ $(cat "$ROOT/usb/API_VERSION") == 1 ]]

if grep -RIE 'bootmnt|mason-arch' "$ROOT/usb" --exclude='test-usb-layout.sh'; then
  echo 'The restored USB workflow must not depend on the obsolete bootmnt/mason-arch mount.' >&2
  exit 1
fi

echo 'USB layout, configuration, and launcher assertions passed.'
