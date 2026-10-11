SleepGuard 0.4.3 improves monitoring reliability and removes the old background service.

- The menu-bar app now owns the Go monitor as a child process. Closing the window keeps monitoring active; quitting or an app crash closes the child. Abnormal child exits are retried.
- “Start at login” controls the main app separately. Disabling it keeps the current monitor running, and quitting preserves the next-login preference.
- Old LaunchAgent definitions, the monitor helper, migration entry points and CLI `service` commands are removed. Command-line monitoring remains available through foreground `sleepguard watch`. UI controls consistently refer to monitoring.
- Pause, resume and blackout changes are checked again immediately before automatic termination, so an acknowledged control change prevents a previously authorized signal.
- Failed preflight checks keep notifications active and retry later. Once a termination signal has been attempted, it is not repeated for the same incident.
- Saving rules or settings detects changes made elsewhere and preserves the unsaved draft instead of overwriting newer data.
- Monitor health shows the worker's actual sampling progress, errors and overdue samples separately from UI refreshes.

Existing rules, configuration and history are retained. Legacy standalone service users must stop their old service before using the new monitor; this release does not include an automatic migration entry point.

Validation includes Go race/vet checks, Swift checks, child-process lifecycle tests, 11 isolated login/update-recovery scenarios, an arm64 app build and strict package verification. Real login/reboot and a public 0.4.2 to 0.4.3 upgrade remain separate acceptance items.

Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
