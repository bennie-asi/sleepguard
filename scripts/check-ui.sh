#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/sleepguard-ui-check.XXXXXX")"
arch_name="$(uname -m)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -target "$arch_name-apple-macosx13.0" \
  -module-cache-path "$project_dir/work/swift-cache" \
  -o "$check_dir/duration-check" \
  "$project_dir/macos/Sources/SleepGuard/ViewState.swift" \
  "$project_dir/macos/Sources/SleepGuard/DurationInput.swift" \
  "$project_dir/macos/Tests/DurationValueChecks.swift"
"$check_dir/duration-check"
xcrun swiftc -swift-version 6 -parse-as-library -target "$arch_name-apple-macosx13.0" \
  -module-cache-path "$project_dir/work/swift-cache" \
  -o "$check_dir/shortcut-check" \
  "$project_dir/macos/Sources/SleepGuard/ViewState.swift" \
  "$project_dir/macos/Sources/SleepGuard/Shortcuts.swift" \
  "$project_dir/macos/Tests/ShortcutChecks.swift" \
  "$project_dir/macos/Tests/CheckSupport.swift"
"$check_dir/shortcut-check"
xcrun swiftc -swift-version 6 -parse-as-library -target "$arch_name-apple-macosx13.0" \
  -module-cache-path "$project_dir/work/swift-cache" \
  -o "$check_dir/command-check" \
  "$project_dir/macos/Sources/SleepGuard/BackendCommand.swift" \
  "$project_dir/macos/Tests/BackendCommandChecks.swift" \
  "$project_dir/macos/Tests/CheckSupport.swift"
"$check_dir/command-check"
