#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
DEFAULT_CONFIG="$REPO_ROOT/config/install.conf"

usage() {
  cat <<'USAGE'
Usage:
  ./start.sh [install] [install.sh options]
  ./start.sh preflight [install.sh options]
  ./start.sh COMMAND [archctl arguments]   # on an installed system

With no arguments, this starts installation from the Arch ISO, or resumes the
first-boot workflow when run on the installed system.
USAGE
}

run_installer() {
  local -a args=("$@") command
  local config=$DEFAULT_CONFIG index

  for ((index = 0; index < ${#args[@]}; index++)); do
    if [[ ${args[index]} == --config ]]; then
      ((index + 1 < ${#args[@]})) || {
        echo "--config requires a path" >&2
        exit 2
      }
      config=${args[index + 1]}
      break
    fi
  done

  [[ -r $config ]] || {
    echo "Configuration not found: $config" >&2
    echo "Copy config/install.conf.example to config/install.conf and review it first." >&2
    exit 1
  }

  command=("$REPO_ROOT/install.sh")
  if [[ $config == "$DEFAULT_CONFIG" ]]; then
    command+=(--config "$DEFAULT_CONFIG")
  fi
  command+=("${args[@]}")

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    exec "${command[@]}"
  fi
  exec sudo "${command[@]}"
}

if [[ -r /etc/arch-installer/install.env ]]; then
  case "${1:-finish}" in
    -h|--help)
      usage
      exit 0
      ;;
    install|preflight)
      echo "This system is already installed; use 'archctl finish' or another archctl command." >&2
      exit 2
      ;;
    *)
      if (($# == 0)); then
        exec "$REPO_ROOT/archctl" finish
      fi
      exec "$REPO_ROOT/archctl" "$@"
      ;;
  esac
fi

case "${1:-install}" in
  install)
    (($# == 0)) || shift
    run_installer "$@"
    ;;
  preflight)
    shift
    run_installer --preflight-only "$@"
    ;;
  --*)
    run_installer "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown live-ISO command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
