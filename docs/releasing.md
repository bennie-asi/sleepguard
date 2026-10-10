# Building and releasing

`VERSION` is the source for the display version. The build number is calculated from the three numeric components of that version and must increase for every public release. A Git tag must be `v` plus the exact contents of `VERSION`.

## Local and manual builds

Run `make test check check-ui`, then `make dmg` and `python3 scripts/check-package.py`. `make dmg` produces architecture-specific `dist/SleepGuard-<version>-<arch>.dmg` and a SHA-256 file. The first build downloads Sparkle 2.10.0 after checking its pinned SHA-256. Local builds without `SIGNING_IDENTITY` use ad-hoc signing and are not notarized.

Do not replace a bundle while its App or bundled monitor is alive. The build checks both before compilation and before moving the completed bundle. Use `APP_OUTPUT="$PWD/work/dev/SleepGuard.app" make dmg` for a separate development bundle; pass the same `APP_OUTPUT` to `scripts/check-package.py`. Replacing live executables can invalidate the process identity required by the macOS installer.

**Actions → Build DMG → Run workflow** builds the checked-in `VERSION` for Apple Silicon and Intel. This manual workflow uploads build artifacts but does not create a public Release. The runners are `macos-15` and `macos-15-intel`.

## Public release and update signing

Apple Developer ID and notarization are optional. Without an Apple certificate the workflow builds ad-hoc signed installers, as in the earlier releases. If `MACOS_CERTIFICATE_P12` is set, the other Apple credentials below must all be configured. Sparkle signing is independent of Apple signing:

| Secret | Content |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-exported Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that P12 |
| `MACOS_SIGNING_IDENTITY` | Full Developer ID Application identity |
| `APPLE_ID` | Apple account used by `notarytool` |
| `APPLE_APP_PASSWORD` | Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID |
| `SPARKLE_ED25519_PRIVATE_KEY` | Private key matching `SUPublicEDKey` in `macos/Info.plist` |

The Sparkle key is stored under Keychain account `sleepguard`. `work/sparkle-2.10.0/bin/generate_keys --account sleepguard -p` displays only its public key for comparison with `SUPublicEDKey` in `macos/Info.plist`. Never commit the private key or paste it into an issue or build log.

Commit the new `VERSION`, wait for both main-branch builds to pass, then create and push the matching `vX.Y.Z` tag. Tags must match `VERSION` and exceed the latest published Release. Both architectures must pass before a release is created. With `SPARKLE_ED25519_PRIVATE_KEY` configured, the workflow signs both update feeds, uploads all six assets and publishes. With no Sparkle Secret, it creates a **draft** containing the two DMGs and checksums. It never publishes an unsigned or incomplete update feed.

To finish a draft without exporting the local private key:

1. Download the exact two DMGs and checksums from that tag's workflow or draft Release into `work/release-<version>/`. Verify the checksums. Do not sign locally rebuilt replacements for CI assets.
2. Sign each downloaded installer directly through the Keychain:

   ```sh
   SPARKLE_KEYCHAIN_ACCOUNT=sleepguard ARCH=arm64 \
     APPCAST_IMAGE="$PWD/work/release-<version>/SleepGuard-<version>-arm64.dmg" \
     APPCAST_OUTPUT="$PWD/work/release-<version>/appcast-arm64.xml" \
     scripts/build-appcast.sh
   # Repeat with ARCH=x86_64 and the matching image/output names.
   ```

   Run from the checked-out release commit so `VERSION` and release notes match the installers. The signing tool reads the private key; it is never exported or printed.
3. Verify both feeds and installer signatures with `work/sparkle-2.10.0/bin/sign_update --account sleepguard --verify`. Pass only the XML path for feed verification; pass the DMG path and its enclosure's `sparkle:edSignature` for package verification.
4. Attach `appcast-arm64.xml` and `appcast-x86_64.xml` to the draft. Confirm all six filenames, then publish and read back the Release and both latest-feed URLs.

Both feeds are addressed through `releases/latest/download`; no GitHub Pages deployment is needed. Published assets are immutable: use a higher version for fixes. The failed `v0.4.0` tag is retained; `v0.4.1` includes the menu height and publishing repairs.

The first update-enabled installation from `0.3.x` still uses the DMG because older Apps do not contain an updater. Later updates use **立即更新** to download, verify, install and reopen without handling a DMG. Users who enable automatic downloading instead receive the update on App exit.

## Final acceptance

Install the actual release on a real Mac and publish a higher signed release. Verify a one-click upgrade, automatic checks on/off, a queued automatic install canceled by its switch, an update on exit, watcher stopped/running restoration, retained configuration and history, and failures that leave the old App usable. Record whether the actual package uses ad-hoc or Developer ID signing; repeat the acceptance for Developer ID and notarization when those credentials are configured. Test both architectures and the macOS 13 minimum. Local compilation and a synthetically signed appcast do not prove the remote upgrade path.

`python3 scripts/check-update-integration.py` prepares isolated native applications and prints each `LAUNCH_FIXTURE` path. Open that application to continue the check. The coordinator uses the production updater with a loopback feed, a temporary signing key kept in memory, and its own disposable background process. It covers ordinary installation, re-entry after a live bundle was replaced, preservation of a stopped background process, and rejection of a tampered archive before quitting. It does not use the user's configuration, Keychain or Go service. Run a single case with `--case clean_running`, `replaced_running`, `clean_stopped` or `bad_signature`.
