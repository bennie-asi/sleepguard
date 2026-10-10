import Foundation
import Darwin

// NSTask.waitUntilExit uses the launching thread's run loop. An async task can
// resume on a different thread, leaving that wait stuck after the child exits.
// Poll the task's termination state instead, with bounded shutdown and cancellation.
enum BackendCommand {
    static func run(executable: URL, arguments: [String], input: Data? = nil, timeout: TimeInterval = 12) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let task = Process()
            task.executableURL = executable
            task.arguments = arguments
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleepguard-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("stdout"), errorURL = directory.appendingPathComponent("stderr"), inputURL = directory.appendingPathComponent("stdin")
            for url in [outputURL, errorURL, inputURL] {
                guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw BackendFailure(message: "无法创建后台命令的临时文件。")
                }
            }
            try (input ?? Data()).write(to: inputURL)
            let output = try FileHandle(forWritingTo: outputURL), errors = try FileHandle(forWritingTo: errorURL), stdin = try FileHandle(forReadingFrom: inputURL)
            defer { try? output.close(); try? errors.close(); try? stdin.close() }
            task.standardOutput = output; task.standardError = errors; task.standardInput = stdin
            try task.run()
            // Cancellation can arrive during launch. Always clean up our own child.
            defer { if task.isRunning { _ = Darwin.kill(task.processIdentifier, SIGKILL) } }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(timeout))
            while task.isRunning {
                try Task.checkCancellation()
                if clock.now >= deadline {
                    task.terminate()
                    let shutdownDeadline = clock.now.advanced(by: .milliseconds(250))
                    while task.isRunning && clock.now < shutdownDeadline { try await Task.sleep(for: .milliseconds(20)) }
                    if task.isRunning { _ = Darwin.kill(task.processIdentifier, SIGKILL) }
                    throw BackendFailure(message: "后台查询超时，请重试。")
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
            guard task.terminationStatus == 0 else {
                let message = (try? String(contentsOf: errorURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw BackendFailure(message: message?.isEmpty == false ? message! : "后台命令执行失败。")
            }
            return try Data(contentsOf: outputURL)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
