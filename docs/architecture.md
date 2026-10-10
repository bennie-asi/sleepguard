# Architecture

SleepGuard consists of a native SwiftUI menu bar application and a bundled Go
executable. The app owns windows, app discovery, shortcuts, screen controls,
notification permissions, Keychain access and the launchd registration. Go owns
power collection, process identity, rules, scheduling, SQLite history and the
notification dispatcher.

The boundary is a small JSON CLI (`sleepguard ui ...`), not an HTTP listener.
Requests and replies use bounded private process pipes or temporary files.
Configuration updates use a revision check and change only the relevant page;
editing a notification channel does not save unsaved rule or timing drafts.

## Monitoring

`watch` obtains an exclusive file lock and loops at `monitor.interval`. IOKit
returns structured power assertions. Process creation time, canonical path,
UID, boot identity and delegation metadata are used to attribute an assertion.
Uncertain attribution remains diagnostic-only. The engine applies idle and
wake grace periods, consecutive sampling, reminders and processing deadlines.
The automatic termination path refreshes configuration, control versions,
assertions and process identity before each signal.

## Manual actions

The UI confirms the target and sends a key plus the full observed process
identity. `internal/control` collects current assertions and independently
inspects the PID again. Protected paths, other users, the current process,
SleepGuard, recycled PIDs and cleared requests are rejected. Normal GUI exit
uses `NSRunningApplication.terminate`; unbundled tasks receive SIGTERM. Force
uses SIGKILL. Each action and its observed result are recorded separately.
A timeout means "not confirmed exited", never an implicit escalation.

## Blackout

A black borderless window at screen-saver level is created for every current
`NSScreen`. Screen changes rebuild the covers. Local input restores all covers.
IOPM assertions temporarily prevent idle system and display sleep; explicit
system sleep still works. The Go store receives a renewable 60-second hold,
renewed every 15 seconds. Holding and releasing invalidate in-flight processing
versions. Existing snoozes are never deleted. If the GUI crashes, the process's
IOPM assertions disappear and the hold expires.

## Notifications and credentials

The dispatcher sends enabled channels independently, in parallel. Results are
stored per channel and grouped by delivery round. The Go Telegram path accepts
an environment token for standalone CLI usage. For Keychain channels it invokes
the bundled native app with `--send-keychain-telegram`. That process reads the
item non-interactively and sends HTTPS directly; it never emits the token.

Creating and reading the item therefore share a signing identity. Only an
explicit user notification test allows the OS authorization dialog. No
Keychain operations run as part of opening the app or refreshing status.
Ad-hoc signatures change on rebuilding; Developer ID signing is needed for
stable access across upgrades. System notification delivery similarly uses the
signed native executable and does not request permission from the background.

## Distribution

The app bundle contains Swift and Go executables, original app artwork and
SMAppService LaunchAgent definitions. `make dmg` produces a compressed HFS+
installer, an Applications symlink and a deterministic icon layout. No runtime
configuration or private credentials are copied into the bundle.

GitHub Actions test and package on native arm64 and Intel runners. Manual builds
produce artifacts. Version tags additionally publish a Release. Signing and
notarization are optional; missing credentials produce an explicitly
unnotarized build rather than a false success claim.
