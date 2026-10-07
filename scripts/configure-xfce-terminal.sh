#!/usr/bin/env bash
# Xfce Terminal uses xfconf; terminalrc is only imported once on migration.
set -Eeuo pipefail

(( $# == 1 )) || { echo 'Expected one custom-command argument' >&2; exit 2; }
command=$1
channel=xfce4-terminal

# Provisioning may run before the first graphical login. Start a temporary
# session bus in that case so xfconfd can persist the user's channel to disk.
if [[ ${XFCE_TERMINAL_IN_BUS:-} != 1 && ! -S ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus ]]; then
  exec env -u XDG_RUNTIME_DIR dbus-run-session -- env XFCE_TERMINAL_IN_BUS=1 bash "$0" "$command"
fi
if [[ ${XFCE_TERMINAL_IN_BUS:-} != 1 ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
fi

changed=false
set_property() {
  local property=$1 type=$2 desired=$3 current
  if ! current=$(xfconf-query --channel "$channel" --property "$property" 2>/dev/null) \
    || [[ $current != "$desired" ]]; then
    xfconf-query --channel "$channel" --property "$property" --type "$type" --set="$desired"
    changed=true
  fi
}

set_property /custom-command string "$command"
if [[ -n $command ]]; then
  set_property /run-custom-command bool true
else
  set_property /run-custom-command bool false
fi

if [[ $changed == true ]]; then
  echo XFCE_TERMINAL_CHANGED
fi
