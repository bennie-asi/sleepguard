# Building and releasing

`VERSION` is the source for the display version. The build number is calculated from the three numeric components of that version and must increase for every public release. A Git tag must be `v` plus the exact contents of `VERSION`.

## Local and manual builds

Run `make test check check-ui`, then `make dmg` and `python3 scripts/check-package.py`. `make dmg` produces architecture-specific `dist/SleepGuard-<version>-<arch>.dmg` and a SHA-256 file. The first build downloads Sparkle 2.10.0 after checking its pinned SHA-256. Local builds without `SIGNING_IDENTITY` use ad-hoc signing and are not notarized.

**Actions → Build DMG → Run workflow** builds the checked-in `VERSION` for Apple Silicon and Intel. This manual workflow uploads build artifacts but does not create a public Release. The runners are `macos-15` and `macos-15-intel`.

## Public automatic-update release

Before tagging, configure these GitHub Actions Secrets from the Apple Developer account and the Sparkle signing key used by this App:

| Secret | Content |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-exported Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that P12 |
| `MACOS_SIGNING_IDENTITY` | Full Developer ID Application identity |
| `APPLE_ID` | Apple account used by `notarytool` |
| `APPLE_APP_PASSWORD` | Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID |
| `SPARKLE_ED25519_PRIVATE_KEY` | Private key matching `SUPublicEDKey` in `macos/Info.plist` |

The Sparkle key was created under Keychain account `sleepguard`. `scripts/fetch-sparkle.sh` fetches the pinned `generate_keys` tool; `work/sparkle-2.10.0/bin/generate_keys --account sleepguard -p` displays its public key for comparison. Export the private key with the same tool's `-x` option into a temporary file, add its contents as the GitHub Secret, and remove the temporary file. Never commit the key or paste it into an issue or build log. A missing or mismatched Secret stops the tag build before publishing.

For the first update-enabled release, commit `VERSION=0.4.0` with this implementation, run the local checks, then create and push `v0.4.0` from that commit. The tag workflow rejects a version that does not match `VERSION` or does not exceed the latest published Release. It builds and signs both App bundles, notarizes and staples both DMGs, recalculates checksums, generates Sparkle-signed `appcast-arm64.xml` and `appcast-x86_64.xml`, then creates the GitHub Release with all six assets. Both feeds are addressed through `releases/latest/download`; no GitHub Pages deployment is needed. A failure in either architecture blocks Release creation. Never replace assets under an existing version tag; create a higher version instead.

The first `0.4.0` installation from an older version still uses the DMG because older Apps do not contain an updater. From this version onward, the user clicks **立即更新** in the App to download, verify, install and reopen without handling a DMG. Users who enable automatic downloading instead receive the update on App exit.

## Final acceptance

Before announcing automatic updates, install the actual Developer ID release on a real Mac and publish a higher signed test release. Verify a one-click upgrade, automatic checks on/off, a queued automatic install canceled by its switch, an update on exit, watcher stopped/running restoration, retained configuration and history, and failures that leave the old App usable. Test both architectures and the macOS 13 minimum. Local compilation and a synthetically signed appcast do not prove the remote upgrade path.
