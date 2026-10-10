import AppKit
import IOKit.pwr_mgt
import Darwin

@MainActor final class ScreenController {
    private final class Cover: NSWindow {
        override var canBecomeKey: Bool { true }
    }
    private var covers: [NSWindow] = []
    private var eventMonitor: Any?
    private var displayObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var assertions: [IOPMAssertionID] = []
    private var openedAt = Date.distantPast
    private var onRestore: (() -> Void)?
    var active: Bool { !covers.isEmpty }

    func blackout(onRestore: @escaping () -> Void) throws {
        guard !active else { return }
        guard !NSScreen.screens.isEmpty else { throw BackendFailure(message: "没有可用的显示器。") }
        self.onRestore = onRestore
        // Both assertions expire with the process and only affect this session.
        for type in [kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionTypeNoDisplaySleep] {
            var identifier: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "SleepGuard all-display blackout" as CFString, &identifier)
            guard result == kIOReturnSuccess else { restore(); throw BackendFailure(message: "无法保持屏幕黑屏，请重试。") }
            assertions.append(identifier)
        }
        openedAt = Date()
        rebuildCovers()
        NSCursor.hide()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            let restored = MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.openedAt) > 0.4 else { return false }
                self.restore(); return true
            }
            return restored ? nil : event
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildCovers() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        }
    }
    private func rebuildCovers() {
        for window in covers { window.close() }; covers.removeAll()
        for screen in NSScreen.screens {
            let window = Cover(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: true)
            window.backgroundColor = .black
            window.isOpaque = true; window.hasShadow = false; window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false; window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless(); covers.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        covers.first?.makeKey()
    }
    func restore() {
        let wasActive = active
        for window in covers { window.close() }; covers.removeAll()
        for identifier in assertions { IOPMAssertionRelease(identifier) }; assertions.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }; sleepObserver = nil
        if wasActive { NSCursor.unhide() }
        let callback = onRestore; onRestore = nil; callback?()
    }
    static func lockScreen() throws {
        // macOS exposes no public desktop lock API. Resolve login.framework at
        // runtime, fail explicitly if unavailable, and never simulate keystrokes.
        guard let library = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY) else {
            throw BackendFailure(message: "此系统暂不支持一键锁屏，请使用 ⌃⌘Q。")
        }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "SACLockScreenImmediate") else { throw BackendFailure(message: "无法调用系统锁屏，请使用 ⌃⌘Q。") }
        typealias Lock = @convention(c) () -> Int32
        let lock = unsafeBitCast(symbol, to: Lock.self)
        guard lock() == 0 else { throw BackendFailure(message: "系统未完成锁屏，请使用 ⌃⌘Q。") }
    }
}
