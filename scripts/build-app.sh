#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/SleepGuard.app"
arch_name="${ARCH:-$(uname -m)}"
[[ "$arch_name" == arm64 || "$arch_name" == x86_64 ]] || { echo 'ARCH must be arm64 or x86_64' >&2; exit 1; }
version="${VERSION:-0.3.2}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be x.y.z' >&2; exit 1; }
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/work/swift-cache" "$app_dir/Contents/Library/LaunchAgents"
cp "$project_dir/macos/io.sleepguard.agent.plist" "$app_dir/Contents/Library/LaunchAgents/io.sleepguard.agent.plist"
cp "$project_dir/macos/io.sleepguard.app.agent.plist" "$app_dir/Contents/Library/LaunchAgents/io.sleepguard.app.agent.plist"
cp "$project_dir/macos/Info.plist" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion ${BUILD_NUMBER:-10}" "$app_dir/Contents/Info.plist"
cd "$project_dir"
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$project_dir/work/swift-cache" -o "$project_dir/work/render-app-icon" scripts/render-app-icon.swift
"$project_dir/work/render-app-icon" "$project_dir/work/SleepGuard.iconset"
iconutil --convert icns "$project_dir/work/SleepGuard.iconset" --output "$app_dir/Contents/Resources/SleepGuard.icns"
rm -rf "$project_dir/work/SleepGuard.iconset" "$project_dir/work/render-app-icon"
go_arch=arm64
if [[ "$arch_name" == x86_64 ]]; then go_arch=amd64; fi
export MACOSX_DEPLOYMENT_TARGET=13.0
CGO_ENABLED=1 GOOS=darwin GOARCH="$go_arch" CC="clang -arch $arch_name" "${GO:-go}" build -trimpath -ldflags='-s -w' -o "$app_dir/Contents/Resources/sleepguard" ./cmd/sleepguard
xcrun swiftc -swift-version 6 -parse-as-library -O -target "$arch_name-apple-macosx13.0" -module-cache-path "$project_dir/work/swift-cache" -o "$app_dir/Contents/MacOS/SleepGuard" macos/Sources/SleepGuard/*.swift
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
    codesign --force --sign - --identifier io.sleepguard.backend "$app_dir/Contents/Resources/sleepguard"
    codesign --force --sign - "$app_dir"
else
    codesign --force --sign "$identity" --options runtime --timestamp --identifier io.sleepguard.backend "$app_dir/Contents/Resources/sleepguard"
    codesign --force --sign "$identity" --options runtime --timestamp "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"
touch "$app_dir"
printf 'Built %s (%s, %s)\n' "$app_dir" "$version" "$arch_name"
