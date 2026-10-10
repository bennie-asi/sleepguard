# Building and releasing

## One-click build

1. Open **Actions → Build DMG → Run workflow** on GitHub.
2. Enter an `x.y.z` version, then run it on `main`.
3. Download the two architecture-specific artifacts from the completed run.

Each artifact contains a DMG and a SHA-256 file. A manual run does not create a
public release. The workflow uses `macos-15` (arm64) and `macos-15-intel` (x64).

## Public release

Run checks locally, then push an annotated version tag:

```sh
make test check check-ui
VERSION=0.3.0 make dmg
git tag -a v0.3.0 -m 'SleepGuard 0.3.0'
git push origin v0.3.0
```

The tag workflow tests both architectures, builds installers, and publishes
both DMGs and checksum files using the notes in `docs/release-notes.md`. A
failed architecture prevents the release job. Updating a published version
requires a new tag; the workflow does not overwrite existing releases.

## Optional signing and notarization

Without a certificate, builds use ad-hoc signing and are **not notarized**.
Do not describe these downloads as Apple-verified. Users may need macOS's
"Open Anyway" flow; never recommend disabling Gatekeeper.

For stable signing identity and notarization, set these repository Actions
Secrets from your own Apple Developer account:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 export of a Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that exported P12 |
| `MACOS_SIGNING_IDENTITY` | Full Developer ID Application identity name |
| `APPLE_ID` | Apple account for notarization |
| `APPLE_APP_PASSWORD` | Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID |

The workflow imports the certificate only into a temporary runner keychain,
uses hardened-runtime signatures, submits the DMG to `notarytool`, staples the
ticket, validates it and recalculates the checksum. The temporary keychain is
removed even after failure. No signing credentials belong in this repository.

Locally, a pre-existing signing identity can be selected with
`SIGNING_IDENTITY='Developer ID Application: ...' make dmg`. The local script
signs but does not automatically notarize.

## Validation before publishing

Mount the final DMG. Check the app icon, Applications link, two-icon layout and
signature. Install via drag and reopen from Applications. Confirm menu dismissal,
refresh, service start/stop, native authorization, screen controls and shortcuts
on a real Mac. Only claim the checks that were actually executed.
