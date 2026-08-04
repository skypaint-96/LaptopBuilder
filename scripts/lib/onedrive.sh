#!/usr/bin/env bash

ONEDRIVE_BOOTSTRAP_UNIT='arch-workstation-onedrive-bootstrap.service'
ONEDRIVE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/onedrive"
ONEDRIVE_COMPLETE_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-complete"
ONEDRIVE_FAILED_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-failed"
ONEDRIVE_BACKUP_ROOT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/arch-workstation/folder-backups"

initialise_onedrive_state() {
  mkdir -p "$ONEDRIVE_STATE_DIR" "$ONEDRIVE_BACKUP_ROOT_BASE"
  chmod 0700 "$ONEDRIVE_STATE_DIR" "$ONEDRIVE_BACKUP_ROOT_BASE"
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

onedrive_bootstrap_active() {
  systemctl --user is-active --quiet "$ONEDRIVE_BOOTSTRAP_UNIT"
}

onedrive_bootstrap_failed() {
  systemctl --user is-failed --quiet "$ONEDRIVE_BOOTSTRAP_UNIT" || [[ -s $ONEDRIVE_FAILED_MARKER ]]
}

onedrive_bootstrap_complete() {
  [[ -s $ONEDRIVE_COMPLETE_MARKER ]] && onedrive_links_ready
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
    # directory remains in the dated backup for manual comparison.
    rsync -a --ignore-existing -- "$source/" "$target/"
    mv -- "$source" "$backup_root/$name"
    info "Preserved the original $name folder at $backup_root/$name"
  fi

  ln -s -- "$target" "$source"
  success "Linked $source -> $target"
}

configure_onedrive_links() {
  local sync_root="$HOME/$ONEDRIVE_SYNC_DIR"
  local backup_root="$ONEDRIVE_BACKUP_ROOT_BASE/$(date +'%Y%m%d-%H%M%S')"
  local name failures=0
  local -a names

  mkdir -p "$sync_root"
  read -r -a names <<< "$ONEDRIVE_LINK_DIRS"
  for name in "${names[@]}"; do
    migrate_onedrive_link "$name" "$sync_root" "$backup_root" || ((failures += 1))
  done

  if [[ -d $backup_root ]]; then
    cat > "$backup_root/README.txt" <<'EOF_BACKUP'
These folders were retained by arch-workstation before replacing the normal
home-directory paths with OneDrive links. Files with names that already existed
in OneDrive were deliberately not overwritten. Review this backup before deleting it.
EOF_BACKUP
    chmod 0600 "$backup_root/README.txt"
  fi

  ((failures == 0))
}

notify_onedrive() {
  local urgency=$1 title=$2 message=$3
  if bool_true "${ONEDRIVE_NOTIFY_ON_COMPLETION:-true}" && command -v notify-send >/dev/null 2>&1; then
    notify-send --urgency="$urgency" --app-name='Arch Workstation' "$title" "$message" >/dev/null 2>&1 || true
  fi
}
