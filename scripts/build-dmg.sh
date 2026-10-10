#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${APP_OUTPUT:-$project_dir/dist/SleepGuard.app}"
version="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_dir/Contents/Info.plist")}"
architecture="${ARCH:-$(uname -m)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$architecture" == arm64 || "$architecture" == x86_64 || "$architecture" == universal ]] || { echo 'Invalid ARCH' >&2; exit 1; }
codesign --verify --strict "$app_dir"
stage="$(mktemp -d "${TMPDIR:-/tmp}/sleepguard-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_dir" "$stage/SleepGuard.app"
ln -s /Applications "$stage/Applications"
python3 "$project_dir/scripts/dmg-layout.py" "$stage/.DS_Store"
mkdir -p "$project_dir/dist"
image="$project_dir/dist/SleepGuard-$version-$architecture.dmg"
hdiutil create -fs HFS+ -volname 'SleepGuard' -srcfolder "$stage" -format UDZO -imagekey zlib-level=9 -ov "$image"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$image"
fi
hdiutil verify "$image"
(cd "$project_dir/dist" && shasum -a 256 "$(basename "$image")" > "$(basename "$image").sha256")
printf 'Built %s\n' "$image"
