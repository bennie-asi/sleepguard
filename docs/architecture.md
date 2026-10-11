# Architecture

SleepGuard consists of a native SwiftUI menu bar application and a bundled Go
executable. The app owns windows, app discovery, shortcuts, screen controls,
notification permissions, Keychain access and the Go child process. Go owns
power collection, process identity, rules, scheduling, SQLite history and the
notification dispatcher.

The boundary is a small JSON CLI (`sleepguard ui ...`), not an HTTP listener.
Requests and replies use bounded private process pipes or temporary files.
Configuration updates compare the edited page against its original values before
applying the draft to the latest configuration. A backend revision check protects
the subsequent save. Changes to other pages are preserved; a conflicting draft
remains available until explicitly discarded or reconciled.

## Monitoring

`watch` obtains an exclusive file lock and loops at `monitor.interval`. IOKit
returns structured power assertions. Process creation time, canonical path,
UID, boot identity and delegation metadata are used to attribute an assertion.
Uncertain attribution remains diagnostic-only. The engine applies idle and
wake grace periods, consecutive sampling, reminders and processing deadlines.
The automatic termination path refreshes configuration, control versions,
assertions and process identity before each signal. Collection takes place before
the final control lock; pause, resume and blackout changes share this lock with
the final authorization and signal, including SIGKILL. The lock is never held
during collection or the wait between signals. An acknowledged control change
therefore cannot be followed by a previously authorized signal.

Failed preflight checks leave the event eligible for retry after the greater of
one minute or two sampling intervals, with notifications allowed while waiting.
Signal intent is persisted only after successful preflight, immediately before
the syscall. Once a signal has been attempted, later errors do not cause a repeat.

The watcher writes its own startup, attempt, completion and error timestamps to
SQLite. UI snapshots do not update those timestamps. A process that holds the lock
but has no first completion within 30 seconds, or no later completion within the
greater of 30 seconds or three intervals, is displayed as overdue. Restarting
retains diagnostic history but requires a new completion before reporting healthy.

The desktop app owns `watch --exit-on-stdin-close` through `AppMonitor`. Closing
the lifetime pipe stops the child, including after an app crash. Abnormal child
exits are supervised by the app. There are no LaunchAgent registrations, migration
entry points or CLI service commands. Standalone CLI monitoring uses foreground
`watch`; login startup is a separate main-app setting.

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

The app bundle contains the Swift app, the Go executable, original app artwork
and Sparkle. It contains no monitor helper or LaunchAgent definitions. `make dmg` produces a compressed HFS+
installer, an Applications symlink and a deterministic icon layout. No runtime
configuration or private credentials are copied into the bundle.

GitHub Actions test and package on native arm64 and Intel runners. Manual builds
produce artifacts. Version tags additionally publish a Release. Signing and
notarization are optional; missing credentials produce an explicitly
unnotarized build rather than a false success claim.
