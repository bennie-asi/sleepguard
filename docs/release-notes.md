SleepGuard 0.4.8 fixes an empty power assertion snapshot being reported as a monitoring failure and improves status feedback.

- A successful IOKit read with no per-process assertions is treated as an empty snapshot, so the monitor continues sampling.
- The most recent monitoring error shows its full date and time. It can be dismissed, stays hidden across refreshes and app restarts, and reappears for a new error.
- Confirmation messages, including manual refresh success, float over the management window instead of moving its content.

The native empty-result regression check, Go race tests, Swift checks, and package validation cover this release. Existing rules, configuration, and event history are retained. Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
