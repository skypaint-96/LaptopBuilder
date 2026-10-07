#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/xfconf-query" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $1 == --channel && $2 == xfce4-terminal && $3 == --property ]]
property=$4
file=$MOCK_CHANNEL/${property#/}
if (($# == 4)); then
  [[ -f $file ]] || exit 1
  cat "$file"
else
  [[ $5 == --type ]]
  case $property:$6 in
    /custom-command:string|/run-custom-command:bool) ;;
    *) exit 2 ;;
  esac
  [[ $7 == --set=* ]]
  printf '%s\n' "${7#--set=}" > "$file"
fi
EOF
chmod +x "$tmp/xfconf-query"
export PATH="$tmp:$PATH" MOCK_CHANNEL="$tmp" XFCE_TERMINAL_IN_BUS=1
command='env TITLE="work desk" sh -c '\''echo $HOME; echo {{ 1 + 1 }}; echo x=y'\'''
[[ $(bash "$ROOT/scripts/configure-xfce-terminal.sh" "$command") == XFCE_TERMINAL_CHANGED ]]
[[ $(cat "$tmp/custom-command") == "$command" ]]
[[ $(cat "$tmp/run-custom-command") == true ]]
[[ -z $(bash "$ROOT/scripts/configure-xfce-terminal.sh" "$command") ]]
[[ $(bash "$ROOT/scripts/configure-xfce-terminal.sh" '') == XFCE_TERMINAL_CHANGED ]]
[[ $(cat "$tmp/run-custom-command") == false ]]
[[ -z $(cat "$tmp/custom-command") ]]
[[ -z $(bash "$ROOT/scripts/configure-xfce-terminal.sh" '') ]]
echo 'Xfce Terminal xfconf writer tests passed.'
