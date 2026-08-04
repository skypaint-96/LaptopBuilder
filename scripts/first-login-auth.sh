#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/auth"
COMPLETE_MARKER="$STATE_DIR/first-login-complete"
mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"
[[ -f $COMPLETE_MARKER ]] && exit 0
# The login that starts the initial archctl finish workflow may occur before the
# configured applications exist. Leave the autostart pending until setup has
# reached its complete state, then offer authentication on the next login.
[[ -f /var/lib/arch-workstation/complete ]] || exit 0

# Give the Xfce session, keyring, network applet, and default browser time to settle.
sleep 8

if command -v xfce4-terminal >/dev/null 2>&1; then
  exec xfce4-terminal \
    --disable-server \
    --title='Arch Workstation authentication' \
    --hold \
    --command='/usr/local/bin/archctl auth --first-login'
fi

if command -v xterm >/dev/null 2>&1; then
  exec xterm -T 'Arch Workstation authentication' -e /usr/local/bin/archctl auth --first-login
fi

/usr/local/bin/archctl auth --first-login
