# Contributing

Thanks for helping SleepGuard make macOS sleep issues easier to understand.

Open an issue with your macOS version, CPU architecture, observed behavior and
expected result. Remove Bot Tokens, private notification contents and personal
paths from logs or screenshots. Use the issue templates for bugs and feature
requests. Security-sensitive reports should follow `SECURITY.md`.

## Development

Use macOS with Command Line Tools/Xcode, Go 1.27+, Swift 6 and Python 3.

```sh
make test check check-ui
make app
make run-app
make dmg
```

Keep changes focused. Preserve unknown application attribution, PID reuse
protection, user snoozes, page-specific config updates and independent delivery
results. Automatic actions remain opt-in. No credential values may appear in
configuration, errors, event history, screenshots or build artifacts.

Tests for process/control changes must exercise rejected identities and stale
state. UI layout changes normally need native visual verification rather than
implementation-mirroring tests. Distinguish simulations from real app, display,
permission and notification acceptance in `macos/VALIDATION.md`.

## Adding a notification provider

The channel config and dispatcher factory are the extension boundary. Add a
provider-specific sender, validation and redacted error handling; keep channel
IDs stable and store separate delivery results. Update the Swift provider list
only when sending is implemented, then document credentials and supported
capabilities. A disabled provider must never make external requests.

The project uses the MIT license. Contributions should be compatible with it.
