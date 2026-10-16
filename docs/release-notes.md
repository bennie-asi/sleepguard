SleepGuard 0.4.10 makes long event histories easier to browse with categories and pagination.

- Filter by monitoring, notifications, application actions, pause and screen controls, or other events.
- Browse 20, 50, or 100 groups per page, jump to a page, or go directly to the newest or oldest records. Category and paging controls remain visible while scrolling.
- SQLite filters and loads only the requested page. The native list creates rows on demand, and notification results from the same round stay together across page boundaries.
- Older pages stay in place when new events arrive. Refresh returns to the latest first page, and changing pages resets the scroll position.

Regression checks cover paging beyond the previous 100-event display limit, complete notification rounds, stable browsing snapshots, retention cleanup, category boundaries, legacy databases, and failed requests. Native Apple Silicon interaction was checked with 100,000 isolated events. Existing rules, configuration, and event history are retained, as are the startup and quit fixes from 0.4.9. Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
