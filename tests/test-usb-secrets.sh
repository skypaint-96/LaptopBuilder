#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for command in gpg jq sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "USB secret test skipped because $command is unavailable." >&2
    exit 0
  fi
done

TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/config/install.conf.example" "$TEMP/install.conf"
test_pin=$(printf '%s%s' 123 456)
jq -n \
  --arg username testuser \
  --arg user_password example-user-password \
  --arg luks_passphrase example-luks-passphrase \
  --arg tpm2_pin "$test_pin" \
  --arg media_unlock_passphrase example-media-passphrase \
  '{username: $username, user_password: $user_password, luks_passphrase: $luks_passphrase, tpm2_pin: $tpm2_pin, media_unlock_passphrase: $media_unlock_passphrase}' \
  > "$TEMP/secrets.json"
chmod 0600 "$TEMP/secrets.json"

"$ROOT/usb/secrets.sh" create \
  --config "$TEMP/install.conf" \
  --input "$TEMP/secrets.json" \
  --output "$TEMP/install-secrets.gpg"

[[ -s $TEMP/install-secrets.gpg ]]
[[ $(stat -c '%a' "$TEMP/install-secrets.gpg") == 600 ]]
! grep -q testuser "$TEMP/install-secrets.gpg.meta"
"$ROOT/usb/secrets.sh" inspect --input "$TEMP/install-secrets.gpg"

printf '%s' 'example-media-passphrase' > "$TEMP/passphrase"
chmod 0600 "$TEMP/passphrase"
"$ROOT/usb/secrets.sh" materialize \
  --config "$TEMP/install.conf" \
  --input "$TEMP/install-secrets.gpg" \
  --output-dir "$TEMP/runtime" \
  --passphrase-file "$TEMP/passphrase"

[[ $(cat "$TEMP/runtime/username") == testuser ]]
[[ $(cat "$TEMP/runtime/user-password") == example-user-password ]]
[[ $(cat "$TEMP/runtime/luks-passphrase") == example-luks-passphrase ]]
[[ $(cat "$TEMP/runtime/tpm2-pin") == "$test_pin" ]]
[[ $(stat -c '%a' "$TEMP/runtime") == 700 ]]
while IFS= read -r file; do
  [[ $(stat -c '%a' "$file") == 600 ]]
done < <(find "$TEMP/runtime" -maxdepth 1 -type f)

unsafe_output="/var/lib/archws-secret-test-$$"
if "$ROOT/usb/secrets.sh" materialize \
    --config "$TEMP/install.conf" \
    --input "$TEMP/install-secrets.gpg" \
    --output-dir "$unsafe_output" \
    --passphrase-file "$TEMP/passphrase" >/dev/null 2>&1; then
  echo 'Credentials were unexpectedly materialized outside a temporary runtime tree.' >&2
  exit 1
fi
[[ ! -e $unsafe_output ]]

short_bundle_passphrase=$(printf '%s%s' sh ort)
jq --arg pass "$short_bundle_passphrase" '.media_unlock_passphrase = $pass' \
  "$TEMP/secrets.json" > "$TEMP/short-passphrase.json"
chmod 0600 "$TEMP/short-passphrase.json"
if "$ROOT/usb/secrets.sh" create \
    --config "$TEMP/install.conf" \
    --input "$TEMP/short-passphrase.json" \
    --output "$TEMP/short-passphrase.gpg" </dev/null >/dev/null 2>&1; then
  echo 'A short USB bundle passphrase unexpectedly passed.' >&2
  exit 1
fi

chmod 0644 "$TEMP/secrets.json"
if "$ROOT/usb/secrets.sh" create \
    --config "$TEMP/install.conf" \
    --input "$TEMP/secrets.json" \
    --output "$TEMP/should-not-exist.gpg" </dev/null >/dev/null 2>&1; then
  echo 'An insecure plaintext secret-file mode unexpectedly passed.' >&2
  exit 1
fi

echo 'Encrypted USB secret-bundle tests passed.'
