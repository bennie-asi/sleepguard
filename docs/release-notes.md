SleepGuard 0.4.6 fixes extra blank space above and below the menu bar panel.

- The native menu window now follows the measured content height, keeping its top edge anchored.
- Long menus remain constrained to the available screen height and scroll to the bottom. Switching back to shorter content shrinks the window immediately.
- Menu reopening and screen changes reapply the current height. Management windows are unaffected.

Native window checks cover actual content and window dimensions, content growth and shrinkage, screen height changes, and restoration from a stale window size. A real MenuBarExtra fixture also passed short/long/short visual and scrolling checks. Full release acceptance is recorded separately in the project documentation.

Existing rules, configuration, event history and log retention settings are retained. Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
