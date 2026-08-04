#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${ARCH_WORKSTATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${ARCH_WORKSTATION_CONFIG:-/etc/arch-installer/install.conf}"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"

TARGET=all
FIRST_LOGIN=false
ASSUME_YES=false

usage() {
  cat <<'USAGE'
Usage: archctl auth [all|github|onedrive|vscode|edge|steam|status|reset] [options]

Runs supported interactive login flows without storing credentials in the project.

Options:
  --first-login   Run as the one-time graphical-login wizard
  --yes           Accept supported non-destructive prompts
  -h, --help      Show this help

Folder linking for OneDrive occurs only after authentication and a successful
initial sync. Existing local folders are retained in a dated backup directory.
USAGE
}

while (($#)); do
  case "$1" in
    all|github|onedrive|vscode|edge|steam|status|reset)
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
BACKUP_ROOT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/arch-workstation/folder-backups"
mkdir -p "$AUTH_STATE_DIR" "$GUI_MARKER_DIR" "$BACKUP_ROOT_BASE"
chmod 0700 "$AUTH_STATE_DIR" "$GUI_MARKER_DIR" "$BACKUP_ROOT_BASE"

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

onedrive_authenticated() {
  [[ -s $HOME/.config/onedrive/refresh_token ]]
}

onedrive_links_ready() {
  local sync_root="$HOME/$ONEDRIVE_SYNC_DIR" name source target
  local -a names
  read -r -a names <<< "$ONEDRIVE_LINK_DIRS"
  for name in "${names[@]}"; do
    source="$HOME/$name"
    target="$sync_root/$name"
    [[ -L $source ]] || return 1
    [[ $(readlink -f -- "$source") == $(readlink -m -- "$target") ]] || return 1
  done
}

mark_gui_authenticated() {
  local provider=$1
  printf '%s\n' "$(date --iso-8601=seconds)" > "$GUI_MARKER_DIR/$provider"
  chmod 0600 "$GUI_MARKER_DIR/$provider"
}

gui_authenticated() {
  [[ -f $GUI_MARKER_DIR/$1 ]]
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

  if bool_true "$AUTH_ONEDRIVE"; then
    if onedrive_authenticated; then
      printf '[ OK ] OneDrive has a local OAuth refresh token.\n'
    else
      printf '[ .. ] OneDrive is not authenticated.\n'
      ((failures += 1))
    fi
    if onedrive_links_ready; then
      printf '[ OK ] OneDrive home-folder links are configured.\n'
    else
      printf '[ .. ] OneDrive home-folder links are not complete.\n'
      ((failures += 1))
    fi
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
  ask "Authenticate GitHub CLI using the browser now?" yes || return 1
  gh auth login --hostname github.com --web --git-protocol "$GITHUB_GIT_PROTOCOL"
  gh auth setup-git --hostname github.com
  github_authenticated || { warn 'GitHub CLI authentication did not validate.'; return 1; }
  success 'GitHub CLI authentication is valid and Git credential handling is configured.'
}

migrate_onedrive_link() {
  local name=$1 sync_root=$2 backup_root=$3
  local source="$HOME/$name" target="$sync_root/$name"

  mkdir -p "$target"
  if [[ -L $source ]]; then
    if [[ $(readlink -f -- "$source") == $(readlink -m -- "$target") ]]; then
      success "$source already links to $target"
      return 0
    fi
    warn "$source is already a symbolic link to another location; leaving it unchanged."
    return 1
  fi

  if mountpoint -q "$source" 2>/dev/null; then
    warn "$source is a mount point; refusing to replace it with a symbolic link."
    return 1
  fi

  if [[ -e $source && ! -d $source ]]; then
    warn "$source exists but is not a directory; leaving it unchanged."
    return 1
  fi

  if [[ -d $source ]]; then
    mkdir -p "$backup_root"
    chmod 0700 "$backup_root"
    # Preserve remote files on name collisions. The complete original local
    # directory is then retained in the dated backup for manual comparison.
    rsync -a --ignore-existing -- "$source/" "$target/"
    mv -- "$source" "$backup_root/$name"
    info "Preserved the original $name folder at $backup_root/$name"
  fi

  ln -s -- "$target" "$source"
  success "Linked $source -> $target"
}

configure_onedrive_links() {
  local sync_root="$HOME/$ONEDRIVE_SYNC_DIR"
  local backup_root="$BACKUP_ROOT_BASE/$(date +'%Y%m%d-%H%M%S')"
  local name failures=0
  local -a names

  mkdir -p "$sync_root"
  read -r -a names <<< "$ONEDRIVE_LINK_DIRS"
  for name in "${names[@]}"; do
    migrate_onedrive_link "$name" "$sync_root" "$backup_root" || ((failures += 1))
  done

  if [[ -d $backup_root ]]; then
    cat > "$backup_root/README.txt" <<EOF_BACKUP
These folders were retained by arch-workstation before replacing the normal
home-directory paths with OneDrive links. Files with names that already existed
in OneDrive were deliberately not overwritten. Review this backup before deleting it.
EOF_BACKUP
    chmod 0600 "$backup_root/README.txt"
  fi

  ((failures == 0))
}

authenticate_onedrive() {
  command -v onedrive >/dev/null 2>&1 || { warn 'OneDrive is not installed; run archctl apply first.'; return 1; }
  mkdir -p "$HOME/.config/onedrive"
  chmod 0700 "$HOME/.config/onedrive"

  if ! onedrive_authenticated; then
    ask "Authenticate the OneDrive client using the browser now?" yes || return 1
    onedrive
  fi
  onedrive_authenticated || { warn 'OneDrive authentication did not create a refresh token.'; return 1; }
  success 'OneDrive authentication material is present in the local user configuration.'

  if onedrive_links_ready; then
    success 'OneDrive home-folder links are already configured.'
    if bool_true "$ONEDRIVE_ENABLE_SERVICE"; then
      systemctl --user enable --now onedrive.service
    fi
    return 0
  fi

  info 'Displaying the effective OneDrive configuration.'
  onedrive --display-config
  info 'Running the required non-destructive OneDrive dry run.'
  onedrive --sync --verbose --dry-run

  ask "Run the initial OneDrive synchronisation and then link $ONEDRIVE_LINK_DIRS?" yes || {
    warn 'OneDrive is authenticated, but the initial sync and folder links were deferred.'
    return 1
  }

  onedrive --sync --verbose
  configure_onedrive_links || {
    warn 'One or more existing home folders could not be linked safely. Review the warnings and rerun this command.'
    return 1
  }
  # Upload any non-conflicting files copied from the original local folders.
  onedrive --sync --verbose

  if bool_true "$ONEDRIVE_ENABLE_SERVICE"; then
    systemctl --user enable --now onedrive.service
    success 'The OneDrive user service is enabled and running.'
  fi
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
    rm -f "$AUTH_COMPLETE_MARKER"
    rm -f "$GUI_MARKER_DIR"/* 2>/dev/null || true
    success 'First-login authentication markers were reset. Existing application tokens were not removed.'
    ;;
  github)
    authenticate_github
    ;;
  onedrive)
    authenticate_onedrive
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
      success 'All enabled authentication items are complete.'
    fi
    ;;
esac
