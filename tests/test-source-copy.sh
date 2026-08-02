#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir=$(mktemp -d)
secret_probe="$ROOT/config/source-copy-probe.secret"

cleanup() {
  rm -f "$secret_probe"
  rm -rf "$temp_dir"
}
trap cleanup EXIT

printf 'must-not-be-copied\n' > "$secret_probe"
chmod 0600 "$secret_probe"

INSTALL_ROOT="$temp_dir/target"
REPO_ROOT="$ROOT"
CONFIG_FILE="$ROOT/config/install.conf.example"
mkdir -p "$INSTALL_ROOT"

# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/install/20-base.sh
source "$ROOT/scripts/install/20-base.sh"

copy_repository_to_target

target="$INSTALL_ROOT/opt/arch-workstation"
[[ -r $target/README.md ]] || { echo 'Tracked repository files were not copied.' >&2; exit 1; }
[[ -x $target/install.sh ]] || { echo 'Installer executable mode was not preserved.' >&2; exit 1; }
[[ -x $target/start.sh ]] || { echo 'Compatibility start wrapper was not copied as executable.' >&2; exit 1; }
[[ -x $target/upgrade-existing.sh ]] || { echo 'Upgrade helper was not copied as executable.' >&2; exit 1; }
[[ -x $target/scripts/provision.sh ]] || { echo 'Script executable mode was not restored.' >&2; exit 1; }
[[ -r $target/config/install.conf ]] || { echo 'Runtime configuration was not staged.' >&2; exit 1; }
[[ ! -e $target/.git ]] || { echo 'Git internals were copied into the target.' >&2; exit 1; }
[[ ! -e $target/config/source-copy-probe.secret ]] || { echo 'An untracked secret probe was copied.' >&2; exit 1; }
[[ -s $target/BUILD_COMMIT ]] || { echo 'Source provenance was not recorded.' >&2; exit 1; }

if git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 && \
  [[ $(readlink -f "$(git -C "$ROOT" rev-parse --show-toplevel)") == $(readlink -f "$ROOT") ]]; then
  expected=$(git -C "$ROOT" rev-parse HEAD)
  actual=$(<"$target/BUILD_COMMIT")
  [[ $actual == "$expected" || $actual == "$expected-dirty" ]] \
    || { echo "Unexpected Git provenance: $actual" >&2; exit 1; }
else
  grep -qx 'source-archive' "$target/BUILD_COMMIT" \
    || { echo 'Archive provenance marker was not recorded.' >&2; exit 1; }
fi

echo 'Installed source snapshot test passed.'