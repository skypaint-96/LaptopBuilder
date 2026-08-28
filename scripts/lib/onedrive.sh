#!/usr/bin/env bash

ONEDRIVE_BOOTSTRAP_UNIT='arch-workstation-onedrive-bootstrap.service'
ONEDRIVE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/onedrive"
ONEDRIVE_COMPLETE_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-complete"
ONEDRIVE_FAILED_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-failed"
ONEDRIVE_BACKUP_ROOT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/arch-workstation/folder-backups"
ONEDRIVE_PROFILE_NAME=default
ONEDRIVE_CONFIG_DIR="$HOME/.config/onedrive"
ONEDRIVE_PROFILE_SYNC_DIR=${ONEDRIVE_SYNC_DIR:-OneDrive}
ONEDRIVE_PROFILE_LINK_DIRS=${ONEDRIVE_LINK_DIRS:-}

onedrive_profile_confdir() {
  local profile=$1
  if [[ $profile == default ]]; then
    printf '%s\n' "$HOME/.config/onedrive"
  else
    printf '%s\n' "$HOME/.config/onedrive-%s" "$profile"
  fi
}

set_onedrive_profile() {
  ONEDRIVE_PROFILE_NAME=$1
  ONEDRIVE_PROFILE_SYNC_DIR=$2
  ONEDRIVE_PROFILE_LINK_DIRS=$3
  ONEDRIVE_CONFIG_DIR=$(onedrive_profile_confdir "$ONEDRIVE_PROFILE_NAME")
  ONEDRIVE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-workstation/onedrive/$ONEDRIVE_PROFILE_NAME"
  ONEDRIVE_COMPLETE_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-complete"
  ONEDRIVE_FAILED_MARKER="$ONEDRIVE_STATE_DIR/bootstrap-failed"
}

onedrive_profile_specs() {
  local profile name sync_dir link_csv links
  if [[ -n ${ONEDRIVE_PROFILES:-} ]]; then
    for profile in $ONEDRIVE_PROFILES; do
      IFS=':' read -r name sync_dir link_csv <<< "$profile"
      links=${link_csv//,/ }
      [[ -n ${links// /} ]] || links=''
      printf '%s\t%s\t%s\n' "$name" "$sync_dir" "$links"
    done
  else
    printf 'default\t%s\t%s\n' "$ONEDRIVE_SYNC_DIR" "$ONEDRIVE_LINK_DIRS"
  fi
}

onedrive_profile_count() {
  local count=0 profile
  while IFS=$'\t' read -r profile _; do
    [[ -n $profile ]] && ((count += 1))
  done < <(onedrive_profile_specs)
  printf '%s\n' "$count"
}

initialise_onedrive_state() {
  mkdir -p "$ONEDRIVE_STATE_DIR" "$ONEDRIVE_BACKUP_ROOT_BASE"
  chmod 0700 "$ONEDRIVE_STATE_DIR" "$ONEDRIVE_BACKUP_ROOT_BASE"
}

write_onedrive_profile_config() {
  mkdir -p "$ONEDRIVE_CONFIG_DIR"
  chmod 0700 "$ONEDRIVE_CONFIG_DIR"
  cat > "$ONEDRIVE_CONFIG_DIR/config" <<EOF_ONEDRIVE_CONFIG
# Managed by arch-workstation. Authentication tokens are stored separately by
# the OneDrive client in this user's private configuration directory.
sync_dir = "~/$ONEDRIVE_PROFILE_SYNC_DIR"
skip_dotfiles = "${ONEDRIVE_SKIP_DOTFILES:-true}"
skip_symlinks = "${ONEDRIVE_SKIP_SYMLINKS:-true}"
use_recycle_bin = "${ONEDRIVE_USE_RECYCLE_BIN:-true}"
EOF_ONEDRIVE_CONFIG
  chmod 0600 "$ONEDRIVE_CONFIG_DIR/config"
}

onedrive_authenticated() {
  [[ -s $ONEDRIVE_CONFIG_DIR/refresh_token ]]
}

onedrive_links_ready() {
  local sync_root="$HOME/$ONEDRIVE_PROFILE_SYNC_DIR" name source target
  local -a names
  read -r -a names <<< "$ONEDRIVE_PROFILE_LINK_DIRS"
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
  local sync_root="$HOME/$ONEDRIVE_PROFILE_SYNC_DIR"
  local backup_root="$ONEDRIVE_BACKUP_ROOT_BASE/$(date +'%Y%m%d-%H%M%S')"
  local name failures=0
  local -a names

  mkdir -p "$sync_root"
  read -r -a names <<< "$ONEDRIVE_PROFILE_LINK_DIRS"
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
