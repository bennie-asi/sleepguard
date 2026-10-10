SleepGuard 0.4.1 includes the version page and in-app updater introduced in 0.4.0.

- The menu and version page show the installed version, available update and update progress.
- “Update Now” downloads, verifies, installs and reopens SleepGuard in one action. It restores the prior background-monitor state after relaunch.
- Automatic update checks can be enabled or disabled. Optional background downloads install when SleepGuard exits.
- The menu panel fits its content up to 640 points, or the current screen's available height. Longer content scrolls without a visible scrollbar.
- Apple Silicon and Intel DMGs each have a checksum and a Sparkle-signed update feed.

These builds use ad-hoc app signing and are not Apple-notarized. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key. The full upgrade and background restoration flow between two public versions still needs testing.

The original sleep monitoring, rules, notifications and screen controls remain available.
