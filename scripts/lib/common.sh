#!/usr/bin/env bash

PROJECT_NAME="arch-workstation"
INSTALL_ROOT="${INSTALL_ROOT:-/mnt}"
CRYPT_NAME="${CRYPT_NAME:-cryptroot}"
TARGET_MOUNTED_BY_INSTALLER="${TARGET_MOUNTED_BY_INSTALLER:-false}"
CRYPT_OPENED_BY_INSTALLER="${CRYPT_OPENED_BY_INSTALLER:-false}"
STATE_DIR="${STATE_DIR:-/var/lib/arch-workstation}"
SUDO_KEEPALIVE_PID="${SUDO_KEEPALIVE_PID:-}"

_log() {
  local level=$1
  shift
  printf '[%s] %-7s %s\n' "$(date +'%H:%M:%S')" "$level" "$*"
}

info() { _log INFO "$@"; }
warn() { _log WARN "$@" >&2; }
success() { _log OK "$@"; }
die() { _log ERROR "$@" >&2; exit 1; }

bool_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

confirm() {
  local prompt=${1:-Continue?}
  local default=${2:-no}
  local reply suffix

  if [[ $default == yes ]]; then
    suffix='[Y/n]'
  else
    suffix='[y/N]'
  fi

  read -r -p "$prompt $suffix " reply
  reply=${reply:-$default}
  bool_true "$reply"
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "This command must run as root."
}

require_non_root() {
  [[ ${EUID:-$(id -u)} -ne 0 ]] || die "Run this command as the target user, not root."
}

require_commands() {
  local missing=() cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  ((${#missing[@]} == 0)) || die "Missing required commands: ${missing[*]}"
}

start_sudo_keepalive() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    return 0
  fi

  require_commands sudo
  sudo -v
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n -v >/dev/null 2>&1 || exit 0
      sleep 45
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
  if [[ -n ${SUDO_KEEPALIVE_PID:-} ]]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}

partition_path() {
  local disk=$1 number=$2
  if [[ $disk =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$disk" "$number"
  else
    printf '%s%s\n' "$disk" "$number"
  fi
}

wait_for_block_device() {
  local device=$1 attempts=${2:-50}
  local i
  for ((i = 0; i < attempts; i++)); do
    [[ -b $device ]] && return 0
    sleep 0.1
  done
  die "Block device did not appear: $device"
}

read_secret_into() {
  local output_var=$1
  local secret_file=$2
  local prompt=$3
  local require_confirmation=${4:-false}
  local value confirmation mode

  if [[ -n $secret_file ]]; then
    [[ -f $secret_file ]] || die "Secret file not found: $secret_file"
    mode=$(stat -c '%a' "$secret_file")
    [[ $mode =~ ^[46]00$ ]] || die "Secret file $secret_file must have mode 0400 or 0600 (currently $mode)."
    IFS= read -r value < "$secret_file" || true
    [[ -n $value ]] || die "Secret file is empty: $secret_file"
  else
    read -r -s -p "$prompt: " value
    printf '\n'
    [[ -n $value ]] || die "A blank secret is not allowed."
    if bool_true "$require_confirmation"; then
      read -r -s -p "Confirm $prompt: " confirmation
      printf '\n'
      [[ $value == "$confirmation" ]] || die "The values did not match."
    fi
  fi

  printf -v "$output_var" '%s' "$value"
}

efi_var_value() {
  local name=$1 path
  path=$(compgen -G "/sys/firmware/efi/efivars/${name}-*" | head -n 1 || true)
  [[ -n $path && -r $path ]] || return 2
  od -An -t u1 "$path" | awk '{ value=$NF } END { print value }'
}

secure_boot_enabled() {
  [[ $(efi_var_value SecureBoot 2>/dev/null || printf '0') == 1 ]]
}

setup_mode_enabled() {
  [[ $(efi_var_value SetupMode 2>/dev/null || printf '0') == 1 ]]
}

cleanup_target() {
  local rc=0

  if bool_true "$TARGET_MOUNTED_BY_INSTALLER"; then
    if findmnt -rn -R "$INSTALL_ROOT" >/dev/null 2>&1; then
      if umount -R "$INSTALL_ROOT"; then
        TARGET_MOUNTED_BY_INSTALLER=false
      else
        rc=1
      fi
    else
      TARGET_MOUNTED_BY_INSTALLER=false
    fi
  fi

  if bool_true "$CRYPT_OPENED_BY_INSTALLER"; then
    if cryptsetup status "$CRYPT_NAME" >/dev/null 2>&1; then
      if cryptsetup close "$CRYPT_NAME"; then
        CRYPT_OPENED_BY_INSTALLER=false
      else
        rc=1
      fi
    else
      CRYPT_OPENED_BY_INSTALLER=false
    fi
  fi

  return "$rc"
}

shell_quote_file() {
  local path=$1
  shift
  : > "$path"
  local pair key value
  for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    printf '%s=%q\n' "$key" "$value" >> "$path"
  done
}
