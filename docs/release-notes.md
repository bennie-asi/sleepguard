SleepGuard 0.4.2 fixes an installation failure when a running application's files were replaced during development.

- “Update Now” automatically restarts a process whose executable identity is no longer valid, then continues the signed update.
- Normal updates download, verify, quit the old application, install and reopen the new version. The background monitor returns to its previous running or stopped state.
- Failures identify the download, validation or installation stage and retain the underlying reason.
- Local builds refuse to overwrite an application or bundled monitor that is still running. `APP_OUTPUT` allows a separate development bundle.
- Apple Silicon and Intel DMGs each have a checksum and a Sparkle-signed update feed.

These builds use ad-hoc app signing and are not Apple-notarized. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key. Native integration checks cover installation, relaunch, replaced executables, running/stopped background state, and rejection of a tampered package on Apple Silicon. Intel native interaction, automatic installation on exit and its cancellation remain separate acceptance items.

The original sleep monitoring, rules, notifications and screen controls remain available.
