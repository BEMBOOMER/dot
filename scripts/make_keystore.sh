#!/usr/bin/env bash
set -euo pipefail

out="${1:-$HOME/.android/dot-release.jks}"
alias_name="${KEY_ALIAS:-dot}"
mkdir -p "$(dirname "$out")"
keytool -genkeypair -v -keystore "$out" -alias "$alias_name" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "${KEYSTORE_PASSWORD:?Set KEYSTORE_PASSWORD}" \
  -keypass "${KEY_PASSWORD:?Set KEY_PASSWORD}" \
  -dname "CN=DOT, OU=BEMBOOMER, O=BEMBOOMER, L=Amsterdam, C=NL"
cat <<EOF
Created $out. Configure these GitHub secrets:
ANDROID_KEYSTORE_BASE64=$(base64 < "$out" | tr -d '\n')
ANDROID_KEYSTORE_PASSWORD=$KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS=$alias_name
ANDROID_KEY_PASSWORD=$KEY_PASSWORD
EOF
