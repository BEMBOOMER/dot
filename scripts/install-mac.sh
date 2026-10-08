#!/bin/bash
# Installs or updates DOT on macOS from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/BEMBOOMER/dot/main/scripts/install-mac.sh | bash
#
# Optional: DOT_VERSION=v0.2.3 to pin a release.
set -euo pipefail

repo="BEMBOOMER/dot"
target="/Applications/DOT.app"
bundle_id="com.bemooks.dot"

say() { printf '\033[1;34m•\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m×\033[0m %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Dit script is alleen voor macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 12 )) || fail "DOT vraagt macOS 12 of nieuwer."

tag="${DOT_VERSION:-}"
if [[ -z "$tag" ]]; then
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
    sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Kon de laatste versie niet vinden."
version="${tag#v}"
dmg_name="DOT-$version.dmg"
base="https://github.com/$repo/releases/download/$tag"

work="$(mktemp -d)"
mount_point="$work/mnt"
cleanup() {
  hdiutil detach "$mount_point" -quiet 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

say "DOT $version downloaden"
curl -fL --progress-bar -o "$work/$dmg_name" "$base/$dmg_name"
curl -fsSL -o "$work/checksums-sha256.txt" "$base/checksums-sha256.txt"

say "Controlesom nagaan"
expected="$(awk -v f="$dmg_name" '$2 == f {print $1}' "$work/checksums-sha256.txt")"
actual="$(shasum -a 256 "$work/$dmg_name" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "Controlesom klopt niet. Installatie gestopt."

first_install=1
[[ -d "$target" ]] && first_install=0

if pgrep -xq DOT; then
  say "Draaiende DOT afsluiten"
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -xq DOT || break; sleep 0.25; done
  pkill -x DOT 2>/dev/null || true
fi

say "Installeren in Programma's"
mkdir -p "$mount_point"
hdiutil attach "$work/$dmg_name" -nobrowse -readonly -noautoopen -mountpoint "$mount_point" -quiet
[[ -d "$mount_point/DOT.app" ]] || fail "DOT.app ontbreekt in de DMG."

as_admin() { if [[ -w "/Applications" ]]; then "$@"; else sudo "$@"; fi; }
as_admin rm -rf "$target"
as_admin ditto "$mount_point/DOT.app" "$target"
# Downloaded with curl, so normally no quarantine flag; remove it anyway so Gatekeeper does not block the first start.
as_admin xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

codesign --verify --deep --strict "$target" 2>/dev/null || fail "Handtekening van DOT.app is ongeldig."

say "DOT starten"
open "$target"

echo
if (( first_install )); then
  say "Bediening op afstand: geef DOT toegang tot Toegankelijkheid."
  echo "  Zet DOT aan in de lijst die nu opent. Staat DOT er niet tussen,"
  echo "  sleep DOT dan uit het Finder-venster naar de lijst."
  echo "  macOS laat dit alleen door jou doen, niet door een script."
  open -R "$target"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
  say "Bijgewerkt. Je Toegankelijkheidstoestemming blijft staan (vanaf v0.2.3)."
fi
printf '\033[1;32m✓\033[0m DOT %s staat in Programma'"'"'s.\n' "$version"
