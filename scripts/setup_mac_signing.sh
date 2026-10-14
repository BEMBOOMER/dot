#!/usr/bin/env bash
# One-time setup for stable local macOS signing.
#
# Creates a dedicated keychain with a self-signed "DOT Code Signing"
# certificate. The keychain password is generated and stored in a private file
# outside the repo, so scripts/publish_signed_mac.sh can unlock the keychain
# itself and macOS never asks for a password.
#
# A new certificate changes the app's designated requirement: users grant
# Accessibility once more after the first release signed with it.
set -euo pipefail

identity="DOT Code Signing"
keychain="${DOT_KEYCHAIN:-$HOME/Library/Keychains/dot-signing.keychain-db}"
password_file="${DOT_KEYCHAIN_PASSWORD_FILE:-$HOME/.config/dot/signing-keychain-password}"

if [[ -e "$keychain" ]]; then
  echo "Keychain already exists: $keychain" >&2
  echo "Delete it first with: security delete-keychain \"$keychain\"" >&2
  exit 1
fi

umask 077
mkdir -p "$(dirname "$password_file")"
/usr/bin/openssl rand -base64 32 >"$password_file"
password="$(cat "$password_file")"

work="$(mktemp -d "${TMPDIR:-/tmp}/dot-signing.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cat >"$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $identity
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# LibreSSL (/usr/bin/openssl) writes PKCS#12 files that `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$identity" \
  -inkey "$work/key.pem" -in "$work/cert.pem" \
  -passout "pass:$password" -out "$work/identity.p12"

security create-keychain -p "$password" "$keychain"
# No auto-lock timeout and no lock on sleep.
security set-keychain-settings "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/identity.p12" -k "$keychain" -P "$password" \
  -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a confirmation dialog.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$password" "$keychain" >/dev/null

# Add the keychain to the user search list so codesign finds the identity.
existing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%\"}"
  line="${line#\"}"
  [[ -n "$line" && "$line" != "$keychain" ]] && existing+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${existing[@]}" "$keychain"

echo "Keychain:      $keychain"
echo "Password file: $password_file"
security find-identity -p codesigning "$keychain" | grep -F "$identity"
