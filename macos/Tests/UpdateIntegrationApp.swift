import AppKit
import Combine
import Darwin
import Foundation

@MainActor enum Fixture {
    static var root: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "SleepGuardTestStateRoot") as! String) }
    static func record(_ event: String, _ fields: [String: Any] = [:]) {
        var value = fields
        value["event"] = event; value["pid"] = getpid()
        value["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        guard var data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        data.append(10)
        let fd = open(root.appendingPathComponent("events.jsonl").path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        if fd >= 0 { data.withUnsafeBytes { _ = write(fd, $0.baseAddress, data.count) }; close(fd) }
    }
}

@MainActor final class GuardModel {
    struct Screen { var active = false }
    var screenController = Screen()
    var dirtyRules = false, dirtySettings = false, busy = false
    private var child: Process?
    private var pidFile: URL { Fixture.root.appendingPathComponent("monitor.pid") }
    private func runningPID() -> Int32? {
        guard let value = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(value), pid > 1 else { return nil }
        var path = [UInt8](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(decoding: path.prefix { $0 != 0 }, as: UTF8.self) == Fixture.root.appendingPathComponent("monitor-fixture").path ? pid : nil
    }
    private func startMonitor() throws {
        let process = Process()
        process.executableURL = Fixture.root.appendingPathComponent("monitor-fixture")
        process.arguments = ["600"]
        try process.run(); child = process
        try String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
        Fixture.record("monitor_started", ["monitor_pid": process.processIdentifier])
    }
    func stopMonitor() async throws {
        guard let pid = runningPID() else { return }
        guard kill(pid, SIGTERM) == 0 else { throw BackendFailure(message: "Fixture monitor could not stop") }
        let deadline = Date().addingTimeInterval(5)
        while runningPID() != nil {
            guard Date() < deadline else { throw BackendFailure(message: "Fixture monitor stop timeout") }
            try await Task.sleep(for: .milliseconds(50))
        }
        child = nil
        Fixture.record("monitor_stopped", ["monitor_pid": pid])
    }
    func start() async throws {
        if let recovery = try UpdateRecovery.take() {
            if recovery.watcherWasRunning { try startMonitor() }
            Fixture.record("state_restored", ["was_running": recovery.watcherWasRunning,
                                              "continuing": recovery.continuingUpdate == true])
        } else if !FileManager.default.fileExists(atPath: Fixture.root.appendingPathComponent("initialized").path) {
            if Bundle.main.object(forInfoDictionaryKey: "SleepGuardTestMonitorInitiallyRunning") as? Bool == true { try startMonitor() }
            try Data().write(to: Fixture.root.appendingPathComponent("initialized"))
        }
        UpdateController.shared.start(model: self)
        Fixture.record("ready", ["executable_current": UpdateRelaunch.executableIsCurrent,
                                  "monitor_running": runningPID() != nil])
    }
    func prepareForUpdate(continuingUpdate: Bool = false) async throws {
        let running = runningPID() != nil
        try await stopMonitor()
        try UpdateRecovery(previousBuild: UpdateController.shared.build, watcherWasRunning: running,
                           createdAt: Date(), continuingUpdate: continuingUpdate ? true : nil).save()
        Fixture.record("prepared", ["was_running": running, "continuing": continuingUpdate])
    }
    func restoreAfterFailedUpdate() async {
        if let recovery = try? UpdateRecovery.take(), recovery.watcherWasRunning { try? startMonitor() }
    }
}

@MainActor final class UpdateFixtureDelegate: NSObject, NSApplicationDelegate {
    let model = GuardModel()
    var window: NSWindow?
    var label: NSTextField?
    var timer: Timer?
    var finishing = false
    var lastError: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SleepGuard update check " + UpdateController.shared.version
        let label = NSTextField(labelWithString: "Starting update check…")
        label.frame = NSRect(x: 20, y: 35, width: 440, height: 120)
        window.contentView?.addSubview(label); self.label = label; self.window = window
        window.center(); window.makeKeyAndOrderFront(nil)
        Task {
            do { try await model.start() }
            catch { Fixture.record("fixture_error", ["message": error.localizedDescription]) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }
    func tick() async {
        let updater = UpdateController.shared
        label?.stringValue = "Version \(updater.version), PID \(getpid())\n\(updater.status)\n\(updater.error ?? "")"
        let request = Fixture.root.appendingPathComponent("request-update")
        if FileManager.default.fileExists(atPath: request.path), updater.ready {
            try? FileManager.default.removeItem(at: request)
            Fixture.record("requested", ["executable_current": UpdateRelaunch.executableIsCurrent])
            updater.installNow()
        }
        if let error = updater.error, error != lastError {
            lastError = error; Fixture.record("update_error", ["message": error, "status": updater.status])
        }
        if FileManager.default.fileExists(atPath: Fixture.root.appendingPathComponent("finish").path), !finishing {
            finishing = true; try? await model.stopMonitor(); NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard finishing || UpdateController.shared.installPrepared else { return .terminateCancel }
        Fixture.record("terminated", ["prepared": UpdateController.shared.installPrepared])
        return .terminateNow
    }
}

@main enum UpdateIntegrationApp {
    @MainActor static func main() {
        setenv("SLEEPGUARD_STATE_DIR", Fixture.root.path, 1)
        setenv("SLEEPGUARD_UPDATE_FEED", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as! String, 1)
        if CommandLine.arguments.dropFirst().first == UpdateRelaunch.helperArgument {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task { exit(await UpdateRelaunch.runHelper(arguments: Array(CommandLine.arguments.dropFirst(2)))) }
            NSApplication.shared.run(); return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        let delegate = UpdateFixtureDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
        withExtendedLifetime(delegate) {}
    }
}
