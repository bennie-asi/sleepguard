import AppKit
import Foundation

// Compile with the production model and controllers, replacing only the app entry point.
extension Notification.Name {
    static let sleepGuardShowWindow = Notification.Name("SleepGuardShowWindow")
    static let sleepGuardDismissMenu = Notification.Name("SleepGuardDismissMenu")
}

@main enum LoginStartupChecks {
    @MainActor static func main() async {
        guard let identifier = Bundle.main.bundleIdentifier,
              identifier == "io.sleepguard.tests.login-startup",
              let state = ProcessInfo.processInfo.environment["SLEEPGUARD_STATE_DIR"],
              let backend = ProcessInfo.processInfo.environment["SLEEPGUARD_BACKEND"],
              backend.hasSuffix("/mock-backend.py") else { exit(2) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
        UserDefaults.standard.set(false, forKey: "SUAutomaticallyUpdate")
        let mode = CommandLine.arguments.dropFirst().first ?? ""
        defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        let login = LoginItemController(service: FakeLoginItemService())
        do {
            try await run(mode, state: URL(fileURLWithPath: state), login: login)
            try await AppMonitor.shared.stop()
            print("\(mode): passed")
        } catch {
            try? await AppMonitor.shared.stop()
            print("\(mode): \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor private static func run(_ mode: String, state: URL, login: LoginItemController) async throws {
        let modes = ["manual", "login-disabled", "login-enabled", "already-running", "recovery-stopped",
                     "recovery-expired", "recovery-corrupt", "disable-preserves-monitor", "quit-preserves-login",
                     "update-preparation-stopped", "update-preparation-running"]
        try check(modes.contains(mode), "unknown scenario")
        await login.setEnabled(mode != "login-disabled")
        try check(login.failure == nil, login.failure ?? "")
        try check(login.enabled == (mode != "login-disabled"), "unexpected fixture login item status")
        let initiallyRunning = ["already-running", "disable-preserves-monitor", "update-preparation-running"].contains(mode)
        try Data("stopped".utf8).write(to: state.appendingPathComponent("watcher"))
        if mode == "recovery-stopped" || mode == "recovery-expired" {
            try UpdateRecovery(previousBuild: "0", watcherWasRunning: false,
                               createdAt: Date().addingTimeInterval(mode == "recovery-expired" ? -3600 : 0)).save()
        } else if mode == "recovery-corrupt" {
            try Data("invalid fixture JSON".utf8).write(to: UpdateRecovery.location)
        }
        let model = GuardModel(loginItem: login)
        if initiallyRunning {
            try await model.backend.startMonitor()
            let deadline = Date().addingTimeInterval(5)
            while try await !model.backend.status().watcherRunning {
                try check(Date() < deadline, "fixture monitor failed to start")
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        let baselineStarts = try monitorCalls(state, operation: "watch")
        let manual = ["manual", "disable-preserves-monitor", "update-preparation-stopped", "update-preparation-running"].contains(mode)
        await model.start(launchedAtLogin: !manual)
        let shouldStart = ["login-enabled", "recovery-expired", "recovery-corrupt", "quit-preserves-login"].contains(mode)
        let expectedRunning = shouldStart || initiallyRunning
        let current = try await model.backend.status()
        try check(current.watcherRunning == expectedRunning, "unexpected monitor state after start: \(model.error ?? "no model error")")
        try check(try monitorCalls(state, operation: "watch") - baselineStarts == (shouldStart ? 1 : 0), "monitor start was skipped or repeated")
        // The model's own startup guard must also prevent duplicate starts.
        await model.start(launchedAtLogin: true)
        try check(try monitorCalls(state, operation: "watch") - baselineStarts == (shouldStart ? 1 : 0), "second model.start repeated monitor start")
        if mode == "disable-preserves-monitor" {
            await model.loginItem.setEnabled(false)
            try check(!model.loginItem.enabled && model.loginItem.failure == nil, "login item did not disable")
            let afterDisable = try await model.backend.status()
            try check(afterDisable.watcherRunning, "disabling login stopped the current monitor")
            try check(try monitorCalls(state, operation: "monitor-exited") == 0, "disabling login stopped the child")
        } else if mode == "quit-preserves-login" {
            try await model.stopForQuit()
            let afterQuit = try await model.backend.status()
            model.loginItem.refresh()
            try check(!afterQuit.watcherRunning, "quit did not stop the monitor")
            try check(model.loginItem.enabled, "quit disabled the login item")
            try check(try monitorCalls(state, operation: "monitor-exited") == 1, "quit did not issue exactly one stop")
        } else if mode.hasPrefix("update-preparation-") {
            try await model.prepareForUpdate()
            try check(!AppMonitor.shared.monitoringRequested, "update must stop the owner even when no worker is running")
            try check(try monitorCalls(state, operation: "monitor-exited") == (initiallyRunning ? 1 : 0), "update failed to stop the child")
            let stopped = try await model.backend.status()
            try check(!stopped.watcherRunning, "update preparation left the monitor running")
            let recovery = try JSONDecoder().decode(UpdateRecovery.self, from: Data(contentsOf: UpdateRecovery.location))
            try check(recovery.watcherWasRunning == initiallyRunning, "update recovery lost the original monitoring state")
            await model.restoreAfterFailedUpdate()
            let restored = try await model.backend.status()
            try check(restored.watcherRunning == initiallyRunning, "failed update restored the wrong monitoring state")
            try check(try monitorCalls(state, operation: "watch") - baselineStarts == (initiallyRunning ? 1 : 0), "failed update restarted a previously stopped monitor")
            try check(model.loginItem.enabled, "update preparation changed login settings")
        }
    }

    private static func monitorCalls(_ state: URL, operation: String) throws -> Int {
        let file = state.appendingPathComponent("calls.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { line in
            let arguments = try JSONDecoder().decode([String].self, from: Data(line.utf8))
            return arguments.first == operation
        }.count
    }

    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw BackendFailure(message: message) }
    }
}
