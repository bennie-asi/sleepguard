SleepGuard 0.3.3 fixes background startup and completes the pause/resume workflow.

- Ad-hoc builds use the existing app-associated LaunchAgent, so changing helper hashes does not prevent startup after updates. Developer ID builds keep native ServiceManagement registration with a separately signed monitor helper.
- App bundles are built and signed in a fresh staging directory before replacing the previous build.
- Status and menu bar show running, paused or stopped independently of sleep anomalies. Paused state includes the recovery time and one recovery action; running state shows pause, stopped state shows start.
- Resume can also restart an offline background service. Pause/resume read back immediately, and older refresh results cannot overwrite the new state.
- Startup failures remain visible in the status card with specific signing or permission guidance.

SleepGuard is a native macOS menu bar app for sleep diagnostics and screen controls.

- SwiftUI status, app rules, independent notifications and event history.
- macOS notifications and multiple Telegram channels; tokens stay in Keychain.
- Unified native credential access; background delivery never prompts for a password.
- Confirmed manual quit / force quit with current assertion and process checks.
- All-display blackout with connected display previews, lock screen and inline global shortcut recording (including F1–F19).
- Searchable, grouped application selection with arrow-key navigation and manual entry.
- Bounded, cancellable background commands; refresh errors leave the UI available for retry.
- Compatible ServiceManagement unregistration on the macOS 15 build runners.
- Standard drag-to-Applications DMG installers for Apple Silicon and Intel.

Download `arm64` for Apple Silicon or `x86_64` for Intel. Drag SleepGuard.app to
Applications before opening it or enabling the background service.

Builds without Developer ID credentials are ad-hoc signed and not Apple
notarized. macOS may require the normal Open Anyway flow. Rebuilt ad-hoc apps
may need Keychain authorization again once; stable cross-version authorization
requires the same Developer ID identity.

Future notification provider entries are placeholders, not working integrations.
See the README and validation record for implementation boundaries and test coverage.
