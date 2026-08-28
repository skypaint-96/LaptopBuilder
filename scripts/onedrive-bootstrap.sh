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
PROFILE_ARG=${1:-}
exec 9>"${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/onedrive-bootstrap.lock"
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

bootstrap_profile() {
  local profile=$1 sync_dir=$2 link_dirs=$3 service_name=onedrive.service
  set_onedrive_profile "$profile" "$sync_dir" "$link_dirs"
  initialise_onedrive_state
  if [[ $profile != default ]]; then
    service_name="onedrive@$profile.service"
  fi
  write_onedrive_profile_config

  onedrive_authenticated || die "OneDrive profile '$profile' is not authenticated. Run: archctl auth onedrive"
  rm -f "$ONEDRIVE_FAILED_MARKER"

  # Prevent the normal monitor service racing the one-time initial transaction.
  systemctl --user stop "$service_name" >/dev/null 2>&1 || true

  info "Displaying the effective OneDrive configuration for profile '$profile'."
  onedrive --confdir="$ONEDRIVE_CONFIG_DIR" --display-config
  info "Running the initial real OneDrive synchronisation for profile '$profile'."
  onedrive --confdir="$ONEDRIVE_CONFIG_DIR" --sync --verbose

  if [[ -n $link_dirs ]]; then
    configure_onedrive_links || die "One or more home folders could not be linked safely for OneDrive profile '$profile'."
  fi

  # Upload any non-conflicting files copied from the original local folders.
  if [[ -n $link_dirs ]]; then
    info "Synchronising files merged from the original local folders for profile '$profile'."
    onedrive --confdir="$ONEDRIVE_CONFIG_DIR" --sync --verbose
  fi

  if bool_true "$ONEDRIVE_ENABLE_SERVICE"; then
    systemctl --user enable --now "$service_name"
  fi

  printf '%s\n' "$(date --iso-8601=seconds)" > "$ONEDRIVE_COMPLETE_MARKER"
  chmod 0600 "$ONEDRIVE_COMPLETE_MARKER"
  rm -f "$ONEDRIVE_FAILED_MARKER"
}

while IFS=$'\t' read -r profile sync_dir link_dirs; do
  [[ -z $PROFILE_ARG || $PROFILE_ARG == "$profile" ]] || continue
  bootstrap_profile "$profile" "$sync_dir" "$link_dirs"
done < <(onedrive_profile_specs)
BOOTSTRAP_SUCCEEDED=true
success 'OneDrive initial synchronisation and folder linking completed.'
notify_onedrive normal 'OneDrive setup complete' \
  'Documents, Pictures and Videos are linked and background synchronisation is enabled.'
