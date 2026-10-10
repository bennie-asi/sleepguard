# Security

Please do not include tokens or account passwords in public issues. For a
security-sensitive report, contact the maintainer through the contact methods
on the GitHub profile before disclosing details publicly. Ordinary reproducible
bugs can use the public issue tracker with sensitive data removed.

SleepGuard stores Telegram credentials in macOS Keychain, keeps local data
under the current user, and defaults to notification/observation. Background
helpers cannot open credential authorization dialogs. Process actions validate
the current assertion, process start time, boot identity, path, UID and protected
status before acting.

No app can safely attribute every delegated or kernel power request. Uncertain
attribution does not authorize termination. Global shortcut conflicts cannot
all be enumerated. Screen locking uses a private macOS interface and has an
explicit unsupported-system fallback.

Ad-hoc-signed builds are not notarized. Developer ID signing and notarization
are optional release capabilities, not implied by a passing CI build.
