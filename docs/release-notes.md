SleepGuard 0.4.9 fixes monitoring startup and quitting when macOS omits an unset global sleep override.

- Some Macs return valid power settings without a `SleepDisabled` field. SleepGuard now treats this optional, unset override as allowing sleep, so status refresh and monitoring can start normally. Unreadable settings and invalid explicit values still report an error.
- Quitting verifies that SleepGuard's own monitor has stopped without requiring a fresh power snapshot. A failed status query no longer leaves the app unable to quit.

Regression checks cover missing and invalid sleep overrides, and quitting during status failures with the monitor running or stopped. Go race tests, Swift checks, package validation, and native Apple Silicon startup, sampling, and quit checks passed. Existing rules, configuration, and event history are retained. Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
