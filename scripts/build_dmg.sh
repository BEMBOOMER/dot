#!/usr/bin/env bash
set -euo pipefail

flutter build macos --release
app="build/macos/Build/Products/Release/DOT.app"
codesign --force --deep --sign - "$app"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/dot-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app" "$staging_dir/DOT.app"
ln -s /Applications "$staging_dir/Applications"
rm -f build/DOT.dmg
hdiutil create -volname DOT -srcfolder "$staging_dir" -ov -format UDZO build/DOT.dmg
shasum -a 256 build/DOT.dmg > build/DOT.dmg.sha256
