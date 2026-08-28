#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/onedrive.sh
source "$REPO_ROOT/scripts/lib/onedrive.sh"

TARGET=all
FIRST_LOGIN=false
ASSUME_YES=false
EDGE_PREPARE_ATTEMPTED=false

usage() {
  cat <<'USAGE'
Usage: archctl auth [TARGET] [options]

Targets:
  all               Run all enabled authentication flows (default)
  github            Authenticate GitHub CLI
  onedrive          Authenticate OneDrive and start its initial background sync
  onedrive-status   Show OneDrive bootstrap/service state
  onedrive-logs     Follow the OneDrive initial-sync journal
  vscode            Open Visual Studio Code Settings Sync
  edge              Prepare Edge and open profile-sync settings
  steam             Open Steam sign-in
  status            Summarise all supported authentication state
  reset             Reset local wizard completion markers only

Options:
  --first-login     Run as the one-time graphical-login wizard
  --yes             Accept supported non-destructive prompts
  -h, --help        Show this help

Edge is prepared before browser-based OAuth so its first-run screens do not
interrupt GitHub or OneDrive authentication. OneDrive authentication remains
interactive, but the dry run, initial sync, folder migration, and service setup
run in a background user service.
USAGE
}

while (($#)); do
  case "$1" in
    all|github|onedrive|onedrive-status|onedrive-logs|vscode|edge|steam|status|reset)
      TARGET=$1
      shift
      ;;
    --first-login)
      FIRST_LOGIN=true
      shift
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown authentication option: $1"
      ;;
  esac
done

require_non_root
[[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
load_config "$CONFIG_FILE"
validate_config runtime
[[ $(id -un) == "$USERNAME" ]] || die "Run authentication as configured user '$USERNAME'."

AUTH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/auth"
AUTH_COMPLETE_MARKER="$AUTH_STATE_DIR/first-login-complete"
GUI_MARKER_DIR="$AUTH_STATE_DIR/gui"
EDGE_READY_MARKER="$AUTH_STATE_DIR/edge-first-run-complete"
mkdir -p "$AUTH_STATE_DIR" "$GUI_MARKER_DIR"
chmod 0700 "$AUTH_STATE_DIR" "$GUI_MARKER_DIR"
initialise_onedrive_state

if bool_true "$FIRST_LOGIN" && [[ -f $AUTH_COMPLETE_MARKER ]]; then
  exit 0
fi

ask() {
  local prompt=$1 default=${2:-yes}
  if bool_true "$ASSUME_YES"; then
    return 0
  fi
  confirm "$prompt" "$default"
}

github_authenticated() {
  command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1
}

mark_gui_authenticated() {
  local provider=$1
  printf '%s\n' "$(date --iso-8601=seconds)" > "$GUI_MARKER_DIR/$provider"
  chmod 0600 "$GUI_MARKER_DIR/$provider"
}

gui_authenticated() {
  [[ -f $GUI_MARKER_DIR/$1 ]]
}

prepare_edge_for_oauth() {
  bool_true "$EDGE_PREPARE_BEFORE_OAUTH" || return 0
  [[ -f $EDGE_READY_MARKER ]] && return 0
  bool_true "$EDGE_PREPARE_ATTEMPTED" && return 1
  EDGE_PREPARE_ATTEMPTED=true
  command -v microsoft-edge-stable >/dev/null 2>&1 || {
    warn 'Microsoft Edge is not installed, so browser OAuth preparation was skipped.'
    return 1
  }

  ask 'Open Microsoft Edge now to complete its first-run screens before browser authentication?' yes || return 1
  setsid -f microsoft-edge-stable --new-window edge://newtab >/dev/null 2>&1 \
    || { warn 'Could not launch Microsoft Edge.'; return 1; }
  cat <<'EOF_EDGE'

Complete the Microsoft Edge welcome/privacy/default-browser screens first.
You may also sign in to the Edge profile now, but that is optional at this stage.
Return to this terminal after Edge is ready to open normal web links.
EOF_EDGE
  read -r -p 'Press Enter when the Edge first-run screens are complete... ' _
  ask 'Mark Microsoft Edge as ready for OAuth links?' yes || return 1
  printf '%s\n' "$(date --iso-8601=seconds)" > "$EDGE_READY_MARKER"
  chmod 0600 "$EDGE_READY_MARKER"
  success 'Microsoft Edge first-run preparation was recorded locally.'
}

print_onedrive_background_status() {
  local profile sync_dir link_dirs
  while IFS=$'\t' read -r profile sync_dir link_dirs; do
    set_onedrive_profile "$profile" "$sync_dir" "$link_dirs"
    if onedrive_bootstrap_complete; then
      printf '[ OK ] OneDrive profile %s initial synchronisation and folder linking are complete.\n' "$profile"
    elif onedrive_bootstrap_active; then
      printf '[ .. ] OneDrive profile %s initial synchronisation is running in the background.\n' "$profile"
    elif onedrive_bootstrap_failed; then
      printf '[FAIL] OneDrive profile %s initial synchronisation needs attention.\n' "$profile"
    elif onedrive_authenticated; then
      printf '[ .. ] OneDrive profile %s is authenticated but initial synchronisation has not started.\n' "$profile"
    else
      printf '[ .. ] OneDrive profile %s is not authenticated.\n' "$profile"
    fi
  done < <(onedrive_profile_specs)

  if systemctl --user list-unit-files "$ONEDRIVE_BOOTSTRAP_UNIT" --no-legend 2>/dev/null | grep -q .; then
    systemctl --user --no-pager --full status "$ONEDRIVE_BOOTSTRAP_UNIT" 2>/dev/null || true
  else
    printf '[FAIL] OneDrive bootstrap user service is not installed; run archctl apply.\n'
    return 1
  fi
}

follow_onedrive_logs() {
  command -v journalctl >/dev/null 2>&1 || die 'journalctl is unavailable.'
  echo 'Following OneDrive initial-sync logs. Press Ctrl+C to stop viewing.'
  exec journalctl --user -u "$ONEDRIVE_BOOTSTRAP_UNIT" -f --no-pager
}

authenticate_onedrive_profile() {
  local profile=$1 sync_dir=$2 link_dirs=$3 service_name=onedrive.service
  set_onedrive_profile "$profile" "$sync_dir" "$link_dirs"
  [[ $profile == default ]] || service_name="onedrive@$profile.service"
  mkdir -p "$ONEDRIVE_CONFIG_DIR"
  chmod 0700 "$ONEDRIVE_CONFIG_DIR"

  if ! onedrive_authenticated; then
    prepare_edge_for_oauth || return 1
    ask "Authenticate OneDrive profile '$profile' using the browser now?" yes || return 1
    onedrive --confdir="$ONEDRIVE_CONFIG_DIR"
  fi
  onedrive_authenticated || { warn "OneDrive profile '$profile' authentication did not create a refresh token."; return 1; }
  success "OneDrive profile '$profile' authentication material is present."

  if onedrive_links_ready; then
    success "OneDrive profile '$profile' home-folder links are already configured."
    if bool_true "$ONEDRIVE_ENABLE_SERVICE"; then
      systemctl --user enable --now "$service_name"
    fi
    return 0
  fi

  if onedrive_bootstrap_active; then
    success "OneDrive profile '$profile' initial synchronisation is already running in the background."
    echo "Monitor it with: archctl auth onedrive-status"
    return 0
  fi

  ask "Start the real initial OneDrive sync for profile '$profile' and link ${link_dirs:-no home folders}?" yes || {
    warn "OneDrive profile '$profile' is authenticated, but initial synchronisation was deferred."
    return 1
  }

  if bool_true "$ONEDRIVE_INITIAL_SYNC_BACKGROUND"; then
    start_onedrive_background_bootstrap "$profile"
  else
    /usr/local/bin/arch-workstation-onedrive-bootstrap "$profile"
  fi
}

print_auth_status() {
  local failures=0

  if bool_true "$AUTH_GITHUB_CLI"; then
    if github_authenticated; then
      printf '[ OK ] GitHub CLI is authenticated.\n'
    else
      printf '[ .. ] GitHub CLI is not authenticated.\n'
      ((failures += 1))
    fi
  fi

  if bool_true "$EDGE_PREPARE_BEFORE_OAUTH"; then
    if [[ -f $EDGE_READY_MARKER ]]; then
      printf '[ OK ] Microsoft Edge first-run preparation is complete.\n'
    else
      printf '[ .. ] Microsoft Edge first-run preparation is incomplete.\n'
      ((failures += 1))
    fi
  fi

  if bool_true "$AUTH_ONEDRIVE"; then
    local profile sync_dir link_dirs
    while IFS=$'\t' read -r profile sync_dir link_dirs; do
      set_onedrive_profile "$profile" "$sync_dir" "$link_dirs"
      if onedrive_authenticated; then
        printf '[ OK ] OneDrive profile %s has a local OAuth refresh token.\n' "$profile"
      else
        printf '[ .. ] OneDrive profile %s is not authenticated.\n' "$profile"
        ((failures += 1))
      fi
      if onedrive_bootstrap_complete; then
        printf '[ OK ] OneDrive profile %s initial sync and home-folder links are complete.\n' "$profile"
      elif onedrive_bootstrap_active; then
        printf '[ .. ] OneDrive profile %s initial sync is running in the background.\n' "$profile"
      else
        printf '[ .. ] OneDrive profile %s initial sync and home-folder links are incomplete.\n' "$profile"
        ((failures += 1))
      fi
    done < <(onedrive_profile_specs)
  fi

  if bool_true "$AUTH_VSCODE"; then
    gui_authenticated vscode \
      && printf '[ OK ] VS Code sign-in was confirmed in the workstation wizard.\n' \
      || { printf '[ .. ] VS Code sign-in has not been confirmed.\n'; ((failures += 1)); }
  fi
  if bool_true "$AUTH_EDGE"; then
    gui_authenticated edge \
      && printf '[ OK ] Microsoft Edge sign-in was confirmed in the workstation wizard.\n' \
      || { printf '[ .. ] Microsoft Edge sign-in has not been confirmed.\n'; ((failures += 1)); }
  fi
  if bool_true "$AUTH_STEAM"; then
    gui_authenticated steam \
      && printf '[ OK ] Steam sign-in was confirmed in the workstation wizard.\n' \
      || { printf '[ .. ] Steam sign-in has not been confirmed.\n'; ((failures += 1)); }
  fi

  ((failures == 0))
}

authenticate_github() {
  command -v gh >/dev/null 2>&1 || { warn 'GitHub CLI is not installed; run archctl apply first.'; return 1; }
  if github_authenticated; then
    success 'GitHub CLI is already authenticated.'
    return 0
  fi
  prepare_edge_for_oauth || return 1
  ask 'Authenticate GitHub CLI using the browser now?' yes || return 1
  gh auth login --hostname github.com --web --git-protocol "$GITHUB_GIT_PROTOCOL"
  gh auth setup-git --hostname github.com
  github_authenticated || { warn 'GitHub CLI authentication did not validate.'; return 1; }
  success 'GitHub CLI authentication is valid and Git credential handling is configured.'
}

start_onedrive_background_bootstrap() {
  local profile=${1:-default}
  systemctl --user daemon-reload
  if onedrive_bootstrap_active; then
    success 'OneDrive initial synchronisation is already running in the background.'
    return 0
  fi
  if onedrive_bootstrap_complete; then
    success 'OneDrive initial synchronisation is already complete.'
    return 0
  fi

  systemctl --user reset-failed "$ONEDRIVE_BOOTSTRAP_UNIT" >/dev/null 2>&1 || true
  rm -f "$ONEDRIVE_FAILED_MARKER"
  systemctl --user start --no-block "$ONEDRIVE_BOOTSTRAP_UNIT" "$profile"
  sleep 1
  if onedrive_bootstrap_failed; then
    warn 'The OneDrive background service failed to start.'
    print_onedrive_background_status
    return 1
  fi

  success 'OneDrive initial synchronisation was queued as a background user service.'
  cat <<'EOF_STATUS'
You can close this terminal. Monitor progress with:
  archctl auth onedrive-status
  archctl auth onedrive-logs
EOF_STATUS
}

authenticate_onedrive() {
  command -v onedrive >/dev/null 2>&1 || { warn 'OneDrive is not installed; run archctl apply first.'; return 1; }
  local profile sync_dir link_dirs failures=0
  while IFS=$'\t' read -r profile sync_dir link_dirs; do
    authenticate_onedrive_profile "$profile" "$sync_dir" "$link_dirs" || ((failures += 1))
  done < <(onedrive_profile_specs)
  ((failures == 0))
}

launch_gui_auth() {
  local provider=$1 label=$2
  shift 2
  if gui_authenticated "$provider"; then
    success "$label sign-in was already confirmed."
    return 0
  fi
  ask "Open $label for sign-in now?" yes || return 1
  setsid -f "$@" >/dev/null 2>&1 || { warn "Could not launch $label."; return 1; }
  printf '\nComplete the sign-in in %s, then return to this terminal.\n' "$label"
  read -r -p 'Press Enter when finished... ' _
  if ask "Mark $label authentication as completed?" no; then
    mark_gui_authenticated "$provider"
    success "$label sign-in was recorded locally."
    return 0
  fi
  return 1
}

authenticate_vscode() {
  command -v code >/dev/null 2>&1 || { warn 'Visual Studio Code is not installed; run archctl apply first.'; return 1; }
  launch_gui_auth vscode 'Visual Studio Code Settings Sync' code --new-window
}

authenticate_edge() {
  command -v microsoft-edge-stable >/dev/null 2>&1 \
    || { warn 'Microsoft Edge is not installed; run archctl apply first.'; return 1; }
  prepare_edge_for_oauth || return 1
  launch_gui_auth edge 'Microsoft Edge profile sync' microsoft-edge-stable --new-window edge://settings/profiles
}

authenticate_steam() {
  command -v steam >/dev/null 2>&1 || { warn 'Steam is not installed; run archctl apply first.'; return 1; }
  launch_gui_auth steam 'Steam' steam
}

run_enabled_authentication() {
  local failures=0

  bool_true "$AUTH_GITHUB_CLI" && authenticate_github || {
    bool_true "$AUTH_GITHUB_CLI" && ((failures += 1)) || true
  }
  bool_true "$AUTH_ONEDRIVE" && authenticate_onedrive || {
    bool_true "$AUTH_ONEDRIVE" && ((failures += 1)) || true
  }
  bool_true "$AUTH_VSCODE" && authenticate_vscode || {
    bool_true "$AUTH_VSCODE" && ((failures += 1)) || true
  }
  bool_true "$AUTH_EDGE" && authenticate_edge || {
    bool_true "$AUTH_EDGE" && ((failures += 1)) || true
  }
  bool_true "$AUTH_STEAM" && authenticate_steam || {
    bool_true "$AUTH_STEAM" && ((failures += 1)) || true
  }
  return "$failures"
}

case "$TARGET" in
  status)
    print_auth_status
    ;;
  reset)
    rm -f "$AUTH_COMPLETE_MARKER" "$EDGE_READY_MARKER"
    rm -f "$GUI_MARKER_DIR"/* 2>/dev/null || true
    success 'First-login authentication markers were reset. Existing application tokens and OneDrive data were not removed.'
    ;;
  github)
    authenticate_github
    ;;
  onedrive)
    authenticate_onedrive
    ;;
  onedrive-status)
    print_onedrive_background_status
    ;;
  onedrive-logs)
    follow_onedrive_logs
    ;;
  vscode)
    authenticate_vscode
    ;;
  edge)
    authenticate_edge
    ;;
  steam)
    authenticate_steam
    ;;
  all)
    cat <<'EOF_INTRO'
Arch Workstation authentication wizard
======================================
This wizard uses each application's supported login flow. It does not copy
passwords, OAuth tokens, browser cookies, or active sessions into the project.
Long-running OneDrive setup continues as a background user service.
EOF_INTRO
    failures=0
    run_enabled_authentication || failures=$?
    if bool_true "$FIRST_LOGIN"; then
      printf '%s\n' "$(date --iso-8601=seconds)" > "$AUTH_COMPLETE_MARKER"
      chmod 0600 "$AUTH_COMPLETE_MARKER"
    fi
    if ((failures)); then
      warn "$failures authentication item(s) were skipped or incomplete. Rerun 'archctl auth' at any time."
    else
      success 'All enabled interactive authentication items are complete or queued.'
    fi
    ;;
esac
