#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mapfile -d '' shell_files < <(
  find . -type f \
    \( -name '*.sh' -o -name 'install.sh' -o -name 'archctl' \) \
    -not -path './.git/*' -print0 | sort -z
)

for file in "${shell_files[@]}"; do
  bash -n "$file"
done
printf 'bash -n: checked %d file(s).\n' "${#shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${shell_files[@]}"
  echo 'shellcheck: passed.'
else
  echo 'shellcheck: skipped because shellcheck is not installed.' >&2
fi

python3 -m json.tool vscode/settings.json >/dev/null
python3 tests/check-yaml.py
python3 tests/check-links.py
