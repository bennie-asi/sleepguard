import Foundation
import Darwin

@main enum BackendCommandChecks {
    static func main() async throws {
        // Exercise repeated async thread hops, not just a single synchronous launch.
        for index in 0..<40 {
            let result = try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["sample-\(index)"], timeout: 2)
            precondition(String(decoding: result, as: UTF8.self) == "sample-\(index)\n")
            await Task.yield()
        }
        let large = Data(repeating: 97, count: 512 * 1024)
        let output = try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: large, timeout: 2)
        precondition(output == large, "large output must not deadlock")
        do {
            _ = try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'fixture failure' >&2; exit 7"], timeout: 2)
            fatalError("failed command accepted")
        } catch { precondition(error.localizedDescription == "fixture failure") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleepguard-command-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let arguments = ["-c", "trap '' TERM; echo $$ > \"$1\"; while :; do :; done", "fixture", pidFile.path]
        let start = ContinuousClock.now
        do {
            _ = try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments, timeout: 0.15)
            fatalError("hung command accepted")
        } catch { precondition(error.localizedDescription.contains("超时")) }
        precondition(start.duration(to: .now) < .seconds(2), "timeout must remain bounded even if SIGTERM is ignored")
        try await checkStopped(pidFile)
        try FileManager.default.removeItem(at: pidFile)
        let cancelled = Task { try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments, timeout: 10) }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(FileManager.default.fileExists(atPath: pidFile.path))
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancelled command accepted") }
        catch { precondition(error is CancellationError) }
        try await checkStopped(pidFile)
        let recovered = try await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["recovered"], timeout: 2)
        precondition(String(decoding: recovered, as: UTF8.self) == "recovered\n")
        print("Backend command checks passed (repeated refresh, output, failure, timeout, cancellation, recovery).")
    }
    private static func checkStopped(_ pidFile: URL) async throws {
        let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(text) else { fatalError("missing fixture PID") }
        for _ in 0..<100 {
            if Darwin.kill(pid, 0) == -1 && errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("command child survived cleanup")
    }
}
