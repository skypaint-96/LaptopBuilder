#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-/opt/arch-workstation}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/onedrive.sh
source "$REPO_ROOT/scripts/lib/onedrive.sh"

require_non_root
require_commands flock onedrive rsync systemctl
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run the OneDrive bootstrap as configured user '$USERNAME'."
bool_true "$ENABLE_ONEDRIVE" || die 'OneDrive is disabled in the workstation configuration.'

initialise_onedrive_state
BOOTSTRAP_SUCCEEDED=false
exec 9>"$ONEDRIVE_STATE_DIR/bootstrap.lock"
flock -n 9 || die 'Another OneDrive bootstrap process is already running.'

bootstrap_exit() {
  local exit_code=$?
  if ! bool_true "$BOOTSTRAP_SUCCEEDED"; then
    printf '%s exit=%s\n' "$(date --iso-8601=seconds)" "$exit_code" > "$ONEDRIVE_FAILED_MARKER"
    chmod 0600 "$ONEDRIVE_FAILED_MARKER"
    notify_onedrive critical 'OneDrive setup needs attention' \
      "The initial synchronisation did not finish. Run: archctl auth onedrive-status"
  fi
}
trap bootstrap_exit EXIT

onedrive_authenticated || die 'OneDrive is not authenticated. Run: archctl auth onedrive'
rm -f "$ONEDRIVE_FAILED_MARKER"

# Prevent the normal monitor service racing the one-time initial transaction.
systemctl --user stop onedrive.service >/dev/null 2>&1 || true

info 'Displaying the effective OneDrive configuration.'
onedrive --display-config
info 'Running a non-destructive OneDrive dry run in the background service.'
onedrive --sync --verbose --dry-run
info 'Running the initial OneDrive synchronisation.'
onedrive --sync --verbose

configure_onedrive_links || die 'One or more home folders could not be linked safely.'

# Upload any non-conflicting files copied from the original local folders.
info 'Synchronising files merged from the original local folders.'
onedrive --sync --verbose

if bool_true "$ONEDRIVE_ENABLE_SERVICE"; then
  systemctl --user enable --now onedrive.service
fi

printf '%s\n' "$(date --iso-8601=seconds)" > "$ONEDRIVE_COMPLETE_MARKER"
chmod 0600 "$ONEDRIVE_COMPLETE_MARKER"
rm -f "$ONEDRIVE_FAILED_MARKER"
BOOTSTRAP_SUCCEEDED=true
success 'OneDrive initial synchronisation and folder linking completed.'
notify_onedrive normal 'OneDrive setup complete' \
  'Documents, Pictures and Videos are linked and background synchronisation is enabled.'
