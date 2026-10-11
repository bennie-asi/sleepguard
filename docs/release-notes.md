SleepGuard 0.4.5 fixes an unresponsive menu bar after starting or restoring monitoring.

- A short stdout/stderr message could leave the log reader waiting for 64 KiB while holding a lock needed by the interface. Pipe reads now consume available bytes without blocking.
- Short messages are written while the monitor remains running. Log settings, status refresh and menu actions remain responsive; shutdown still drains the final output.
- Configurable log retention and the content-sized menu from 0.4.4 are retained.

Existing rules, configuration and event history are retained. Log cleanup only targets regular archive files created by SleepGuard.

The regression check keeps a child alive after short stdout/stderr messages, verifies immediate log output and main-actor responsiveness, changes retention settings, and stops the child. Existing output-draining, lifecycle, log rotation and menu-size checks remain in place. Actual release and native acceptance evidence is recorded separately in the project documentation.

Apple Silicon and Intel installers use ad-hoc app signing without Apple notarization. Sparkle verifies the update feed and downloaded package with the existing Ed25519 key.
