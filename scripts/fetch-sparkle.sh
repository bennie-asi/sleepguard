#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="2.10.0"
sha256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
cache="$project_dir/work/sparkle-$version"
archive="$cache/Sparkle-$version.tar.xz"
mkdir -p "$cache"
if [[ ! -f "$archive" ]] || ! printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 --check --status; then
    curl --fail --location --retry 3 --connect-timeout 10 --max-time 180 \
        --output "$archive.tmp" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
    printf '%s  %s\n' "$sha256" "$archive.tmp" | shasum -a 256 --check --status
    mv "$archive.tmp" "$archive"
fi
if [[ ! -d "$cache/Sparkle.framework" || ! -x "$cache/bin/generate_appcast" || ! -x "$cache/bin/generate_keys" ]]; then
    tar -xJf "$archive" -C "$cache" ./Sparkle.framework ./bin/generate_appcast ./bin/generate_keys ./bin/sign_update
fi
printf '%s\n' "$cache"
