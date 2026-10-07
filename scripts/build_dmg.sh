#!/usr/bin/env bash
set -euo pipefail

flutter build macos --release
app="build/macos/Build/Products/Release/DOT.app"
# Hardened runtime requires a real Developer ID signature and notarization.
codesign --force --deep \
  --entitlements macos/Runner/Release.entitlements \
  --sign - "$app"
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
rm -f build/DOT.dmg
hdiutil create -volname DOT -srcfolder "$staging_dir" -ov -format UDZO build/DOT.dmg
shasum -a 256 build/DOT.dmg > build/DOT.dmg.sha256
