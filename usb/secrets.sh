#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config/install.conf"
INPUT_FILE=""
OUTPUT_FILE=""
OUTPUT_DIR=""
PASSPHRASE_FILE=""
COMMAND=""
BUNDLE_PASSPHRASE_MIN_LENGTH=${BUNDLE_PASSPHRASE_MIN_LENGTH:-12}

# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/config.sh
source "$REPO_ROOT/scripts/lib/config.sh"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/usb/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: ./usb/secrets.sh COMMAND [options]

Commands:
  create          Collect missing fields and create an encrypted USB secret bundle
  materialize     Decrypt a bundle into root-readable files in a RAM-backed directory
  collect-runtime Prompt for installation secrets and create RAM-backed files
  inspect         Validate bundle metadata without decrypting secrets

Options:
  --config PATH             Installation configuration
  --input PATH              Plain JSON input for create, encrypted bundle otherwise
  --output PATH             Encrypted bundle destination for create
  --output-dir PATH         Materialized secret directory
  --passphrase-file PATH    Read the bundle unlock passphrase from a 0400/0600 file
USAGE
}

prompt_secret_confirmed() {
  local output_var=$1 label=$2 value confirmation
  read -r -s -p "$label: " value
  printf '\n'
  [[ -n $value ]] || die "$label cannot be blank."
  read -r -s -p "Confirm $label: " confirmation
  printf '\n'
  [[ $value == "$confirmation" ]] || die "$label values did not match."
  printf -v "$output_var" '%s' "$value"
}

json_field() {
  local path=$1 field=$2
  [[ -n $path ]] || return 0
  jq -er --arg field "$field" '.[$field] // empty | select(type == "string")' "$path" 2>/dev/null || true
}

validate_pin() {
  local pin=$1
  if bool_true "$TPM_PIN_NUMERIC_ONLY" && [[ ! $pin =~ ^[0-9]+$ ]]; then
    die 'The TPM2 PIN must contain digits only with TPM_PIN_NUMERIC_ONLY=true.'
  fi
  ((${#pin} >= TPM_PIN_MIN_LENGTH)) \
    || die "The TPM2 PIN must be at least $TPM_PIN_MIN_LENGTH characters."
  if ((${#pin} < 6)); then
    warn 'A TPM2 PIN shorter than six digits is allowed by this profile but is not recommended.'
  fi
}

validate_bundle_passphrase() {
  local passphrase=$1
  ((${#passphrase} >= BUNDLE_PASSPHRASE_MIN_LENGTH)) \
    || die "The USB secret bundle passphrase must be at least $BUNDLE_PASSPHRASE_MIN_LENGTH characters."
}

validate_runtime_output_dir() {
  local output_dir=$1 canonical
  [[ -n $output_dir ]] || die 'The runtime secret directory cannot be blank.'
  canonical=$(readlink -m -- "$output_dir")
  case "$canonical" in
    /run/*|/dev/shm/*|/tmp/*) ;;
    *) die "Refusing to materialize credentials outside a temporary runtime tree: $canonical" ;;
  esac
  [[ $canonical != /run && $canonical != /dev/shm && $canonical != /tmp ]] \
    || die "Refusing to replace the runtime-directory root itself: $canonical"
}

write_secret_json() {
  local destination=$1 username=$2 user_password=$3 luks_passphrase=$4 tpm2_pin=$5
  local created_at=${6:-}

  # Feed secret values over stdin rather than as jq command-line arguments,
  # which would otherwise expose them briefly through the process list.
  if [[ -n $created_at ]]; then
    printf '%s\0%s\0%s\0%s\0' \
      "$username" "$user_password" "$luks_passphrase" "$tpm2_pin" \
      | jq -Rs --arg created_at "$created_at" '
          split("\u0000") as $v
          | {schema: 1, username: $v[0], user_password: $v[1], luks_passphrase: $v[2], tpm2_pin: $v[3], created_at: $created_at}
        ' > "$destination"
  else
    printf '%s\0%s\0%s\0%s\0' \
      "$username" "$user_password" "$luks_passphrase" "$tpm2_pin" \
      | jq -Rs '
          split("\u0000") as $v
          | {schema: 1, username: $v[0], user_password: $v[1], luks_passphrase: $v[2], tpm2_pin: $v[3]}
        ' > "$destination"
  fi
}

read_bundle_passphrase() {
  local output_var=$1 value
  if [[ -n $PASSPHRASE_FILE ]]; then
    require_secure_regular_file "$PASSPHRASE_FILE"
    IFS= read -r value < "$PASSPHRASE_FILE" || true
    [[ -n $value ]] || die "Bundle passphrase file is empty: $PASSPHRASE_FILE"
  else
    read -r -s -p 'USB secret bundle unlock passphrase: ' value
    printf '\n'
    [[ -n $value ]] || die 'The bundle unlock passphrase cannot be blank.'
  fi
  printf -v "$output_var" '%s' "$value"
}

write_materialized_files() {
  local json_path=$1 output_dir=$2
  local username user_password luks_passphrase tpm2_pin
  validate_runtime_output_dir "$output_dir"
  username=$(jq -er '.username | select(type == "string" and length > 0)' "$json_path")
  user_password=$(jq -er '.user_password | select(type == "string" and length > 0)' "$json_path")
  luks_passphrase=$(jq -er '.luks_passphrase | select(type == "string" and length > 0)' "$json_path")
  tpm2_pin=$(jq -er '.tpm2_pin // "" | select(type == "string")' "$json_path")

  if bool_true "$TPM_WITH_PIN"; then
    [[ -n $tpm2_pin ]] || die 'The decrypted bundle has no TPM2 PIN.'
    validate_pin "$tpm2_pin"
  fi

  rm -rf "$output_dir"
  install -d -m 0700 "$output_dir"
  printf '%s' "$username" > "$output_dir/username"
  printf '%s' "$user_password" > "$output_dir/user-password"
  printf '%s' "$luks_passphrase" > "$output_dir/luks-passphrase"
  if [[ -n $tpm2_pin ]]; then
    printf '%s' "$tpm2_pin" > "$output_dir/tpm2-pin"
  fi
  chmod 0600 "$output_dir"/*
}

create_bundle() {
  require_commands gpg jq sha256sum stat
  [[ -n $OUTPUT_FILE ]] || die 'create requires --output PATH.'
  load_config "$CONFIG_FILE"
  validate_config runtime

  if [[ -n $INPUT_FILE ]]; then
    require_secure_regular_file "$INPUT_FILE"
    jq -e 'type == "object"' "$INPUT_FILE" >/dev/null || die 'Secure input must be a JSON object.'
  fi

  local username user_password luks_passphrase tpm2_pin media_passphrase media_confirmation
  username=$(json_field "$INPUT_FILE" username)
  user_password=$(json_field "$INPUT_FILE" user_password)
  luks_passphrase=$(json_field "$INPUT_FILE" luks_passphrase)
  tpm2_pin=$(json_field "$INPUT_FILE" tpm2_pin)
  media_passphrase=$(json_field "$INPUT_FILE" media_unlock_passphrase)

  if [[ -z $username ]]; then
    prompt_with_default username 'Linux username stored in the encrypted bundle' "$USERNAME"
  fi
  [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username in secure input: $username"

  if [[ -z $user_password ]]; then
    prompt_secret_confirmed user_password "Password for $username"
  fi
  if [[ -z $luks_passphrase ]]; then
    prompt_secret_confirmed luks_passphrase 'LUKS recovery passphrase'
  fi
  if bool_true "$TPM_WITH_PIN" && [[ -z $tpm2_pin ]]; then
    prompt_secret_confirmed tpm2_pin 'Daily TPM2 PIN'
  fi
  if bool_true "$TPM_WITH_PIN"; then
    validate_pin "$tpm2_pin"
  fi

  if [[ -z $media_passphrase ]]; then
    prompt_secret_confirmed media_passphrase 'USB secret bundle unlock passphrase'
  else
    media_confirmation=$media_passphrase
    [[ -n $media_confirmation ]] || die 'USB secret bundle passphrase cannot be blank.'
  fi
  validate_bundle_passphrase "$media_passphrase"

  local runtime temp_dir plaintext passfile encrypted_tmp metadata_tmp
  runtime=$(safe_runtime_dir)
  temp_dir=$(mktemp -d "$runtime/archws-secrets.XXXXXX")
  chmod 0700 "$temp_dir"
  plaintext="$temp_dir/secrets.json"
  passfile="$temp_dir/bundle-passphrase"
  encrypted_tmp="$temp_dir/install-secrets.gpg"
  metadata_tmp="$temp_dir/install-secrets.meta"
  cleanup_bundle_temp() {
    rm -rf "$temp_dir"
    rm -f "${output_new:-}" "${metadata_new:-}"
    unset username user_password luks_passphrase tpm2_pin media_passphrase media_confirmation
  }
  trap cleanup_bundle_temp EXIT

  write_secret_json \
    "$plaintext" "$username" "$user_password" "$luks_passphrase" "$tpm2_pin" \
    "$(date --iso-8601=seconds)"
  printf '%s' "$media_passphrase" > "$passfile"
  chmod 0600 "$plaintext" "$passfile"

  gpg --batch --yes --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file "$passfile" --symmetric --cipher-algo AES256 \
    --s2k-cipher-algo AES256 --s2k-digest-algo SHA512 \
    --output "$encrypted_tmp" "$plaintext"

  # Verify the ciphertext before copying it to persistent media.
  gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file "$passfile" --decrypt "$encrypted_tmp" 2>/dev/null \
    | jq -e '.schema == 1 and (.username | length > 0)' >/dev/null

  cat > "$metadata_tmp" <<EOF_META
schema=1
created_at=$(date --iso-8601=seconds)
ciphertext_sha256=$(sha256sum "$encrypted_tmp" | awk '{print $1}')
EOF_META

  local output_new="${OUTPUT_FILE}.new.$$" metadata_new="${OUTPUT_FILE}.meta.new.$$"
  install -D -m 0600 "$encrypted_tmp" "$output_new"
  install -D -m 0644 "$metadata_tmp" "$metadata_new"
  mv -f "$output_new" "$OUTPUT_FILE"
  mv -f "$metadata_new" "${OUTPUT_FILE}.meta"
  rm -rf "$temp_dir"
  unset username user_password luks_passphrase tpm2_pin media_passphrase media_confirmation
  trap - EXIT
  success "Created encrypted USB secret bundle: $OUTPUT_FILE"
  info 'The bundle passphrase is not stored on the USB. It will be requested once at live-boot installation time.'
}

materialize_bundle() {
  require_commands gpg jq
  [[ -n $INPUT_FILE ]] || die 'materialize requires --input PATH.'
  [[ -n $OUTPUT_DIR ]] || die 'materialize requires --output-dir PATH.'
  require_secure_regular_file "$INPUT_FILE"
  load_config "$CONFIG_FILE"
  validate_config runtime

  local passphrase runtime temp_dir passfile plaintext
  read_bundle_passphrase passphrase
  runtime=$(safe_runtime_dir)
  temp_dir=$(mktemp -d "$runtime/archws-decrypt.XXXXXX")
  chmod 0700 "$temp_dir"
  passfile="$temp_dir/passphrase"
  plaintext="$temp_dir/secrets.json"
  printf '%s' "$passphrase" > "$passfile"
  chmod 0600 "$passfile"
  trap 'rm -rf "$temp_dir"; unset passphrase' EXIT

  if ! gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback \
    --passphrase-file "$passfile" --output "$plaintext" --decrypt "$INPUT_FILE" 2>/dev/null; then
    die 'Could not decrypt the USB secret bundle. Check its unlock passphrase.'
  fi
  chmod 0600 "$plaintext"
  jq -e '.schema == 1 and (.username | type == "string")' "$plaintext" >/dev/null \
    || die 'The decrypted secret bundle has an unsupported schema.'
  write_materialized_files "$plaintext" "$OUTPUT_DIR"
  rm -rf "$temp_dir"
  unset passphrase
  trap - EXIT
  success "Materialized installation credentials in RAM at $OUTPUT_DIR"
}

collect_runtime() {
  require_commands jq
  [[ -n $OUTPUT_DIR ]] || die 'collect-runtime requires --output-dir PATH.'
  load_config "$CONFIG_FILE"
  validate_config runtime

  local username user_password luks_passphrase tpm2_pin="" runtime temp_dir json
  prompt_with_default username 'Linux username' "$USERNAME"
  [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: $username"
  prompt_secret_confirmed user_password "Password for $username"
  prompt_secret_confirmed luks_passphrase 'LUKS recovery passphrase'
  if bool_true "$TPM_WITH_PIN"; then
    prompt_secret_confirmed tpm2_pin 'Daily TPM2 PIN'
    validate_pin "$tpm2_pin"
  fi

  runtime=$(safe_runtime_dir)
  temp_dir=$(mktemp -d "$runtime/archws-runtime-secrets.XXXXXX")
  chmod 0700 "$temp_dir"
  json="$temp_dir/secrets.json"
  trap 'rm -rf "$temp_dir"; unset username user_password luks_passphrase tpm2_pin' EXIT
  write_secret_json "$json" "$username" "$user_password" "$luks_passphrase" "$tpm2_pin"
  chmod 0600 "$json"
  write_materialized_files "$json" "$OUTPUT_DIR"
  set_shell_config_value "$CONFIG_FILE" USERNAME "$username"
  chmod 0600 "$CONFIG_FILE"
  rm -rf "$temp_dir"
  unset username user_password luks_passphrase tpm2_pin
  trap - EXIT
  success 'Collected all installation credentials before installation begins.'
}

inspect_bundle() {
  require_commands sha256sum
  [[ -n $INPUT_FILE ]] || die 'inspect requires --input PATH.'
  require_secure_regular_file "$INPUT_FILE"
  [[ -f ${INPUT_FILE}.meta ]] || die "Bundle metadata not found: ${INPUT_FILE}.meta"
  cat "${INPUT_FILE}.meta"
  expected=$(awk -F= '$1 == "ciphertext_sha256" {print $2}' "${INPUT_FILE}.meta")
  actual=$(sha256sum "$INPUT_FILE" | awk '{print $1}')
  [[ -n $expected && $expected == "$actual" ]] || die 'Encrypted bundle checksum does not match its metadata.'
  success 'Encrypted bundle metadata and ciphertext checksum are valid.'
}

COMMAND=${1:-}
case "$COMMAND" in
  -h|--help) usage; exit 0 ;;
esac
[[ -n $COMMAND ]] || { usage >&2; exit 2; }
shift
while (($#)); do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || die '--config requires a path.'
      CONFIG_FILE=$2
      shift 2
      ;;
    --input)
      [[ $# -ge 2 ]] || die '--input requires a path.'
      INPUT_FILE=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die '--output requires a path.'
      OUTPUT_FILE=$2
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die '--output-dir requires a path.'
      OUTPUT_DIR=$2
      shift 2
      ;;
    --passphrase-file)
      [[ $# -ge 2 ]] || die '--passphrase-file requires a path.'
      PASSPHRASE_FILE=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown secrets option: $1"
      ;;
  esac
done

case "$COMMAND" in
  create|materialize|collect-runtime)
    [[ -r $CONFIG_FILE ]] || die "Configuration not found: $CONFIG_FILE"
    ;;
esac
case "$COMMAND" in
  create) create_bundle ;;
  materialize) materialize_bundle ;;
  collect-runtime) collect_runtime ;;
  inspect) inspect_bundle ;;
  *) die "Unknown secrets command: $COMMAND" ;;
esac
