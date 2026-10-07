#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 2
fi

tag="$1"
repo_root="$(git rev-parse --show-toplevel)"
current_tag="$(git describe --exact-match --tags 2>/dev/null || true)"
worktree_root="$repo_root"
temporary_worktree=""
release_dir="$(mktemp -d "${TMPDIR:-/tmp}/dot-release-assets.XXXXXX")"
trap 'rm -rf "$release_dir"' EXIT

if [[ "$current_tag" != "$tag" ]]; then
  temporary_worktree="$(mktemp -d "${TMPDIR:-/tmp}/dot-release.XXXXXX")"
  rmdir "$temporary_worktree"
  git -C "$repo_root" worktree add --detach "$temporary_worktree" "$tag"
  worktree_root="$temporary_worktree"
elif [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  echo "Checkout at tag $tag is not clean." >&2
  exit 1
fi

cleanup() {
  if [[ -n "$temporary_worktree" ]]; then
    git -C "$repo_root" worktree remove --force "$temporary_worktree"
  fi
  rm -rf "$release_dir"
}
trap cleanup EXIT

if [[ -n "${DOT_KEYCHAIN:-}" && -n "${DOT_KEYCHAIN_PASSWORD_FILE:-}" ]]; then
  security unlock-keychain \
    -p "$(cat "$DOT_KEYCHAIN_PASSWORD_FILE")" \
    "$DOT_KEYCHAIN"
fi

version="${tag#v}"
if [[ "$version" == "$tag" || -z "$version" ]]; then
  echo "Tag must start with v and contain a version: $tag" >&2
  exit 1
fi

(
  cd "$worktree_root"
  SIGN_IDENTITY="DOT Code Signing" VERSION="$version" ./scripts/build_dmg.sh
)

dmg_path="$worktree_root/build/DOT-${version}.dmg"
checksum_path="$release_dir/checksums-sha256.txt"
(
  cd "$worktree_root"
  gh release download "$tag" -p checksums-sha256.txt --dir "$release_dir" --clobber
)

new_hash="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
checksum_tmp="$(mktemp "${TMPDIR:-/tmp}/dot-checksums.XXXXXX")"
awk -v filename="DOT-${version}.dmg" -v hash="$new_hash" '
  $2 == filename { print hash "  " filename; replaced = 1; next }
  { print }
  END { if (!replaced) exit 1 }
' "$checksum_path" >"$checksum_tmp"
mv "$checksum_tmp" "$checksum_path"

(
  cd "$worktree_root"
  gh release upload "$tag" \
    "$dmg_path" "$checksum_path" \
    --clobber
)

designated_requirement="$(codesign -dr - "$worktree_root/build/macos/Build/Products/Release/DOT.app" 2>&1)"
printf '%s\n' "$designated_requirement"
printf 'Uploaded assets: %s, checksums-sha256.txt\n' "DOT-${version}.dmg"
