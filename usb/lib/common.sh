#!/usr/bin/env bash

USB_MEDIA_LABEL="${USB_MEDIA_LABEL:-ARCHWS_DATA}"
USB_MEDIA_DIR_NAME="${USB_MEDIA_DIR_NAME:-arch-workstation}"

usb_quote() {
  printf '%q' "$1"
}

normalise_public_git_url() {
  local url=$1
  case "$url" in
    git@github.com:*)
      printf 'https://github.com/%s\n' "${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      printf 'https://github.com/%s\n' "${url#ssh://git@github.com/}"
      ;;
    git@gitlab.com:*)
      printf 'https://gitlab.com/%s\n' "${url#git@gitlab.com:}"
      ;;
    ssh://git@gitlab.com/*)
      printf 'https://gitlab.com/%s\n' "${url#ssh://git@gitlab.com/}"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

validate_git_repository_url() {
  local url=$1
  [[ -n $url ]] || return 0
  [[ $url != -* ]] || die 'A Git repository URL must not begin with a dash.'
  [[ $url != *$'\n'* && $url != *$'\r'* && $url != *$'\t'* && $url != *' '* ]] \
    || die 'A Git repository URL must not contain whitespace or control characters.'

  case "$url" in
    https://*)
      [[ $url =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9._~/%+@:-]+$ ]] \
        || die "Unsupported or unsafe HTTPS Git URL: $url"
      [[ ! $url =~ ^https://[^/]*@ ]] \
        || die 'Refusing to store a Git URL containing inline credentials on the USB.'
      ;;
    ssh://git@*)
      [[ $url =~ ^ssh://git@[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9._~/%+@:-]+$ ]] \
        || die "Unsupported or unsafe SSH Git URL: $url"
      ;;
    git@*:*)
      [[ $url =~ ^git@[A-Za-z0-9.-]+:[A-Za-z0-9._~/%+@-]+$ ]] \
        || die "Unsupported or unsafe SCP-style Git URL: $url"
      ;;
    *)
      die 'Live repository URLs must use credential-free HTTPS or an SSH Git URL.'
      ;;
  esac
}

validate_git_repository_ref() {
  local ref=$1
  [[ -n $ref && $ref != -* ]] || die 'The Git repository ref must be non-empty and must not begin with a dash.'
  command -v git >/dev/null 2>&1 || die 'git is required to validate the repository ref.'
  git check-ref-format --allow-onelevel "$ref" >/dev/null 2>&1 \
    || die "Unsupported or unsafe Git repository ref: $ref"
}

validate_git_repository_source() {
  validate_git_repository_url "$1"
  validate_git_repository_ref "$2"
}

set_shell_config_value() {
  local path=$1 key=$2 value=$3 quoted temp
  [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Unsafe configuration key: $key"
  printf -v quoted '%q' "$value"
  temp=$(mktemp)
  awk -v key="$key" -v replacement="$key=$quoted" '
    $0 ~ "^[[:space:]]*" key "=" {
      if (!written) print replacement
      written = 1
      next
    }
    { print }
    END { if (!written) print replacement }
  ' "$path" > "$temp"
  cat "$temp" > "$path"
  rm -f "$temp"
}

prompt_with_default() {
  local output_var=$1 prompt=$2 default=${3:-} value
  if [[ -n $default ]]; then
    read -r -p "$prompt [$default]: " value
    value=${value:-$default}
  else
    read -r -p "$prompt: " value
  fi
  printf -v "$output_var" '%s' "$value"
}

prompt_boolean() {
  local output_var=$1 prompt=$2 default=${3:-true} answer
  if bool_true "$default"; then
    read -r -p "$prompt [Y/n]: " answer
    answer=${answer:-yes}
  else
    read -r -p "$prompt [y/N]: " answer
    answer=${answer:-no}
  fi
  if bool_true "$answer"; then
    printf -v "$output_var" '%s' true
  else
    printf -v "$output_var" '%s' false
  fi
}

copy_tracked_repository() {
  local source=$1 destination=$2 git_top=""
  rm -rf "$destination"
  mkdir -p "$destination"

  if command -v git >/dev/null 2>&1; then
    git_top=$(git -c "safe.directory=$source" -C "$source" rev-parse --show-toplevel 2>/dev/null || true)
  fi
  if [[ -n $git_top && $(readlink -f "$git_top") == $(readlink -f "$source") ]]; then
    (
      cd "$source"
      git -c "safe.directory=$source" ls-files -z \
        | tar --create --file=- --null \
          --exclude='config/install.conf' \
          --exclude='config/usb-secrets.json' \
          --exclude='config/secrets.conf' \
          --exclude='config/secrets.env' \
          --exclude='*.secret' \
          --exclude='*.key' \
          --exclude='*.pem' \
          --exclude='*.gpg' \
          --exclude='*.iso' \
          --exclude='*.bundle' \
          --exclude='*.zip' \
          --exclude='*.tar.gz' \
          --exclude='usb/output' \
          --exclude='usb/output/*' \
          --exclude='usb/work' \
          --exclude='usb/work/*' \
          --files-from=-
    ) | tar -C "$destination" -xf -
  else
    tar -C "$source" \
      --exclude='.git' \
      --exclude='config/install.conf' \
      --exclude='config/usb-secrets.json' \
      --exclude='config/secrets.conf' \
      --exclude='config/secrets.env' \
      --exclude='*.gpg' \
      --exclude='*.iso' \
      --exclude='*.bundle' \
      --exclude='*.zip' \
      --exclude='*.tar.gz' \
      --exclude='usb/output' \
      --exclude='usb/work' \
      --exclude='build' \
      --exclude='dist' \
      --exclude='*.secret' \
      --exclude='*.key' \
      --exclude='*.pem' \
      -cf - . | tar -C "$destination" -xf -
  fi
}

find_media_partition() {
  local device=${1:-} candidate
  if [[ -n $device ]]; then
    while IFS= read -r candidate; do
      [[ -n $candidate ]] || continue
      if [[ $(lsblk -dnro LABEL "$candidate" 2>/dev/null || true) == "$USB_MEDIA_LABEL" ]] \
        || [[ $(lsblk -dnro PARTLABEL "$candidate" 2>/dev/null || true) == "$USB_MEDIA_LABEL" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(lsblk -nrpo NAME,TYPE "$device" | awk '$2 == "part" {print $1}')
    return 1
  fi

  candidate=$(findfs "LABEL=$USB_MEDIA_LABEL" 2>/dev/null || true)
  [[ -n $candidate ]] || candidate=$(findfs "PARTLABEL=$USB_MEDIA_LABEL" 2>/dev/null || true)
  [[ -n $candidate ]] || return 1
  printf '%s\n' "$candidate"
}

safe_runtime_dir() {
  local base=${XDG_RUNTIME_DIR:-}
  if [[ -n $base && -d $base && -w $base ]]; then
    printf '%s\n' "$base"
  elif [[ -d /dev/shm && -w /dev/shm ]]; then
    printf '%s\n' /dev/shm
  else
    printf '%s\n' /tmp
  fi
}

require_secure_regular_file() {
  local path=$1 mode
  [[ -f $path && ! -L $path ]] || die "Secure input must be a regular, non-symlink file: $path"
  mode=$(stat -c '%a' "$path")
  [[ $mode == 400 || $mode == 600 ]] \
    || die "Secure input $path must have mode 0400 or 0600 (currently $mode)."
}

base64_scalar() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

write_media_environment() {
  local path=$1 repo_url=$2 repo_ref=$3 version=$4 build_commit=$5
  cat > "$path" <<EOF_ENV
ARCHWS_MEDIA_VERSION_B64=$(base64_scalar "$version")
ARCHWS_MEDIA_LABEL_B64=$(base64_scalar "$USB_MEDIA_LABEL")
ARCHWS_REPO_URL_B64=$(base64_scalar "$repo_url")
ARCHWS_REPO_REF_B64=$(base64_scalar "$repo_ref")
ARCHWS_BUILD_COMMIT_B64=$(base64_scalar "$build_commit")
ARCHWS_CACHE_LAYOUT_VERSION=1
EOF_ENV
  chmod 0644 "$path"
}

read_media_environment() {
  local path=$1 key value decoded
  [[ -r $path ]] || return 1
  while IFS='=' read -r key value || [[ -n ${key:-} ]]; do
    case "$key" in
      ARCHWS_MEDIA_VERSION_B64|ARCHWS_MEDIA_LABEL_B64|ARCHWS_REPO_URL_B64|ARCHWS_REPO_REF_B64|ARCHWS_BUILD_COMMIT_B64)
        decoded=$(printf '%s' "$value" | base64 --decode 2>/dev/null) \
          || die "Invalid base64 value in media metadata: $key"
        [[ $decoded != *$'\n'* && $decoded != *$'\r'* ]] \
          || die "Newlines are not allowed in media metadata: $key"
        case "$key" in
          ARCHWS_MEDIA_VERSION_B64) ARCHWS_MEDIA_VERSION=$decoded ;;
          ARCHWS_MEDIA_LABEL_B64) ARCHWS_MEDIA_LABEL=$decoded ;;
          ARCHWS_REPO_URL_B64) ARCHWS_REPO_URL=$decoded ;;
          ARCHWS_REPO_REF_B64) ARCHWS_REPO_REF=$decoded ;;
          ARCHWS_BUILD_COMMIT_B64) ARCHWS_BUILD_COMMIT=$decoded ;;
        esac
        ;;
      ARCHWS_CACHE_LAYOUT_VERSION)
        [[ $value == 1 ]] || die "Unsupported cache layout version: $value"
        ARCHWS_CACHE_LAYOUT_VERSION=$value
        ;;
      ''|'#'*) ;;
      *) die "Unexpected key in media metadata: $key" ;;
    esac
  done < "$path"
}
