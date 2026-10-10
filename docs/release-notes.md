SleepGuard is a native macOS menu bar app for sleep diagnostics and screen controls.

- SwiftUI status, app rules, independent notifications and event history.
- macOS notifications and multiple Telegram channels; tokens stay in Keychain.
- Unified native credential access; background delivery never prompts for a password.
- Confirmed manual quit / force quit with current assertion and process checks.
- All-display blackout, lock screen and configurable global shortcuts.
- Standard drag-to-Applications DMG installers for Apple Silicon and Intel.

Download `arm64` for Apple Silicon or `x86_64` for Intel. Drag SleepGuard.app to
Applications before opening it or enabling the background service.

Builds without Developer ID credentials are ad-hoc signed and not Apple
notarized. macOS may require the normal Open Anyway flow. Rebuilt ad-hoc apps
may need Keychain authorization again once; stable cross-version authorization
requires the same Developer ID identity.

Future notification provider entries are placeholders, not working integrations.
See the README and validation record for implementation boundaries and test coverage.
