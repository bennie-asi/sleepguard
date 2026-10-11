SleepGuard 0.4.4 adds configurable log retention and improves menu panel sizing.

- Runtime logs rotate at the start of a new local day or at 10 MB. The app captures both stdout and stderr from its monitor, preserving final output during shutdown and restart.
- Settings → 日志与历史 now includes log retention days (default 7, range 1–365) and archive count (default 10, range 1–100). Either limit removes the oldest archives; the current log is not counted. Event-history retention remains separate.
- Existing configurations use the new defaults. Saved log preferences apply without restarting the monitor; externally edited preferences are picked up on the app's next refresh.
- The menu measures its content height, shrinks for short content and scrolls when content exceeds the screen limit.

Existing rules, configuration and event history are retained. Log cleanup only targets regular archive files created by SleepGuard.

Validation includes Go race/vet, Swift checks, log retention and complete child-output tests, short/long/short menu sizing checks, 11 isolated login/update scenarios, a native settings-save readback and an arm64 build with strict package verification. Actual menu-bar visual acceptance, multi-display interaction and the public 0.4.3 to 0.4.4 upgrade remain separate acceptance items.

Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
