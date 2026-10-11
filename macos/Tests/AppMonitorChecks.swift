import Foundation
import Darwin

// This executable runs the production owner with a private stdin-only worker.
// It has no app bundle and never calls ServiceManagement or launchctl.
@main enum AppMonitorChecks {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else { exit(2) }
        let mode = arguments[0]
        let worker = URL(fileURLWithPath: arguments[1])
        let state = URL(fileURLWithPath: arguments[2])
        guard ["lifecycle", "orphan-parent", "retry-stop", "retry-resume", "normal-exit"].contains(mode),
              worker.lastPathComponent == "stdin-worker.py",
              state.deletingLastPathComponent() == worker.deletingLastPathComponent(),
              state.deletingLastPathComponent().lastPathComponent.hasPrefix("sleepguard-app-monitor-") else { exit(2) }
        let monitor = AppMonitor(retryDelay: .milliseconds(600))
        do {
            let config = state.appendingPathComponent("config.toml").path
            try monitor.start(executable: worker, config: config, state: state.path)
            try await waitForStarts(1, state: state)
            if ["retry-stop", "retry-resume", "normal-exit"].contains(mode) {
                let deadline = Date().addingTimeInterval(5)
                while monitor.running || (mode == "normal-exit" ? monitor.monitoringRequested : monitor.failure == nil) {
                    guard Date() < deadline else { throw BackendFailure(message: "owner did not observe fixture exit") }
                    try await Task.sleep(for: .milliseconds(20))
                }
                if mode == "normal-exit" {
                    try check(!monitor.monitoringRequested, "normal exit retained a monitoring request")
                    try await Task.sleep(for: .milliseconds(900))
                    try check(try starts(state) == 1, "normal exit unexpectedly restarted")
                } else {
                    try check(monitor.monitoringRequested && !monitor.running, "retry window lost the monitoring request")
                    if mode == "retry-stop" {
                        try await monitor.stop()
                        try check(!monitor.monitoringRequested, "stop retained the pending retry request")
                        try await Task.sleep(for: .milliseconds(900))
                        try check(try starts(state) == 1 && !monitor.running, "stopped retry launched during update preparation")
                    } else {
                        try await waitForStarts(2, state: state)
                        try check(monitor.running && monitor.monitoringRequested, "retry did not restore the requested monitor")
                    }
                }
                try await monitor.stop()
                print("AppMonitor \(mode) passed (retry intent and cancellation).")
                return
            }
            try check(monitor.running, "worker did not stay running while stdin was open")
            if mode == "orphan-parent" {
                try Data("ready".utf8).write(to: state.appendingPathComponent("parent-ready"), options: .atomic)
                // The Python harness kills only this test process. The child must
                // receive EOF without stop(), defer cleanup, or a child signal.
                while true { try await Task.sleep(for: .seconds(1)) }
            }
            try monitor.start(executable: worker, config: config, state: state.path)
            try await Task.sleep(for: .milliseconds(400))
            try check(try starts(state) == 1, "idempotent start launched a second worker")
            try await monitor.stop()
            try check(!monitor.running && !monitor.monitoringRequested, "stop left the worker or request active")
            try await monitor.stop()
            try monitor.start(executable: worker, config: config, state: state.path)
            try await waitForStarts(2, state: state)
            try check(monitor.running, "restart did not produce a live worker")
            try await monitor.stop()
            try check(!monitor.running, "second stop left the worker running")
            try check(monitor.failure == nil, monitor.failure ?? "unexpected supervisor failure")
            print("AppMonitor lifecycle passed (start, idempotence, stdin stop, restart).")
        } catch {
            try? await monitor.stop()
            print("AppMonitor check failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func starts(_ state: URL) throws -> Int {
        let events = state.appendingPathComponent("events.jsonl")
        guard FileManager.default.fileExists(atPath: events.path) else { return 0 }
        return try String(contentsOf: events, encoding: .utf8).split(separator: "\n").filter { line in
            let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return event?["event"] as? String == "start"
        }.count
    }

    private static func waitForStarts(_ count: Int, state: URL) async throws {
        let deadline = Date().addingTimeInterval(5)
        while try starts(state) < count {
            guard Date() < deadline else { throw BackendFailure(message: "worker startup timed out") }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw BackendFailure(message: message) }
    }
}
