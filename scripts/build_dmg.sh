#!/usr/bin/env bash
set -euo pipefail

flutter build macos --release
app="build/macos/Build/Products/Release/DOT.app"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$SIGN_IDENTITY" "$app"
  designated_requirement="$(codesign -dr - "$app" 2>&1)"
  if ! grep -Fq 'certificate root' <<<"$designated_requirement"; then
    echo "Signed macOS app is missing a certificate root designated requirement." >&2
    exit 1
  fi
else
  # Hardened runtime requires a real Developer ID signature and notarization.
  codesign --force --deep \
    --entitlements macos/Runner/Release.entitlements \
    --sign - "$app"
fi
if ! codesign -d --entitlements - "$app" 2>&1 | grep -Fq 'com.apple.security.network.server'; then
  echo "macOS app is missing com.apple.security.network.server entitlement." >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
if codesign -d --entitlements - "$app" 2>&1 | grep -Fq 'com.apple.security.app-sandbox'; then
  echo "macOS remote input requires an unsandboxed app." >&2
  exit 1
fi
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/dot-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app" "$staging_dir/DOT.app"
ln -s /Applications "$staging_dir/Applications"
if [[ -n "${VERSION:-}" ]]; then
  dmg="build/DOT-${VERSION}.dmg"
else
  dmg="build/DOT.dmg"
fi
rm -f "$dmg"
hdiutil create -volname DOT -srcfolder "$staging_dir" -ov -format UDZO "$dmg"
shasum -a 256 "$dmg" > "$dmg.sha256"
