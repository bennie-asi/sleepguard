#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:-$(cat "$project_dir/VERSION")}"
architecture="${ARCH:-$(uname -m)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { echo 'Invalid ARCH' >&2; exit 1; }
if [[ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
    echo 'Missing SPARKLE_ED25519_PRIVATE_KEY for signed appcast' >&2
    exit 1
fi
sparkle_dir="$("$project_dir/scripts/fetch-sparkle.sh")"
image="${APPCAST_IMAGE:-$project_dir/dist/SleepGuard-$version-$architecture.dmg}"
[[ -f "$image" ]] || { echo "Missing $image" >&2; exit 1; }
stage="$(mktemp -d "$project_dir/work/sleepguard-feed.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
cp "$image" "$stage/"
cp "$project_dir/docs/release-notes.md" "$stage/SleepGuard-$version-$architecture.md"
url="https://github.com/bennie-asi/sleepguard/releases/download/v$version"
feed="$stage/appcast-$architecture.xml"
args=(--download-url-prefix "$url/" --embed-release-notes -o "$feed")
printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" | "$sparkle_dir/bin/generate_appcast" --ed-key-file - "${args[@]}" "$stage" 2> "$stage/generate.log"
if grep -q 'does not match' "$stage/generate.log"; then
    echo 'Sparkle private key does not match SUPublicEDKey' >&2
    exit 1
fi
cat "$stage/generate.log" >&2
[[ -s "$feed" ]] || { echo 'Appcast generation failed' >&2; exit 1; }
python3 - "$feed" "$url" "$version" "$architecture" <<'PY'
import sys
import re
import xml.etree.ElementTree as ET
feed, prefix, version, arch = sys.argv[1:]
raw = open(feed, encoding='utf-8').read()
root = ET.parse(feed).getroot()
items = root.findall('./channel/item')
assert len(items) == 1, f'Expected one update, got {len(items)}'
enclosure = items[0].find('enclosure')
assert enclosure is not None
assert enclosure.attrib['url'] == f'{prefix}/SleepGuard-{version}-{arch}.dmg', enclosure.attrib['url']
assert any(key.endswith('edSignature') for key in enclosure.attrib)
assert re.search(r'<!-- sparkle-signatures:\s*edSignature: [A-Za-z0-9+/=]+\s*length: \d+\s*-->', raw), 'Missing signed feed trailer'
print(f'Validated signed appcast for {version} {arch}')
PY
cp "$feed" "${APPCAST_OUTPUT:-$project_dir/dist/appcast-$architecture.xml}"
