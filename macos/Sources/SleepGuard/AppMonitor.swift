import Foundation
import Darwin

// The menu-bar app owns its Go worker. No login item or launchd job is created.
// Keeping stdin open is a lifetime lease: even an app crash closes the pipe and
// lets the Go runner release its lock/database before exiting.
@MainActor final class AppMonitor {
    static let shared = AppMonitor()
    private var process: Process?
    private var lifetime: Pipe?
    private var log: FileHandle?
    private var supervisor: Task<Void, Never>?
    private let retryDelay: Duration
    private(set) var failure: String?
    private(set) var monitoringRequested = false
    var running: Bool { process?.isRunning == true }

    init(retryDelay: Duration = .seconds(30)) { self.retryDelay = retryDelay }

    func start(executable: URL, config: String, state: String) throws {
        guard !running else { return }
        supervisor?.cancel()
        monitoringRequested = false
        try launch(executable: executable, config: config, state: state)
        monitoringRequested = true
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, let process = self.process else { return }
                guard !process.isRunning else { continue }
                let status = process.terminationStatus
                self.closeHandles()
                guard status != 0 else {
                    self.monitoringRequested = false; self.supervisor = nil
                    return
                }
                self.failure = "监控进程意外退出（\(status)），将在 30 秒后重试。"
                do { try await Task.sleep(for: self.retryDelay); try Task.checkCancellation() }
                catch { return }
                do { try self.launch(executable: executable, config: config, state: state) }
                catch {
                    self.failure = error.localizedDescription
                    self.monitoringRequested = false; self.supervisor = nil
                    return
                }
            }
        }
    }

    private func launch(executable: URL, config: String, state: String) throws {
        closeHandles()
        let directory = URL(fileURLWithPath: state)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let logURL = directory.appendingPathComponent("agent.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw BackendFailure(message: "无法创建监控日志。")
            }
        }
        let output = try FileHandle(forWritingTo: logURL)
        try output.seekToEnd()
        let pipe = Pipe(), child = Process()
        child.executableURL = executable
        child.arguments = ["watch", "--exit-on-stdin-close", "--config", config, "--state-dir", state]
        child.standardInput = pipe
        child.standardOutput = output
        child.standardError = output
        do { try child.run() }
        catch { try? output.close(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close(); throw error }
        try? pipe.fileHandleForReading.close()
        process = child; lifetime = pipe; log = output; failure = nil
    }

    func stop() async throws {
        monitoringRequested = false
        supervisor?.cancel(); supervisor = nil
        try? lifetime?.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(8)
        while running && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        if running { process?.terminate() }
        let terminateDeadline = Date().addingTimeInterval(2)
        while running && Date() < terminateDeadline { try await Task.sleep(for: .milliseconds(50)) }
        if let process, process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        let killDeadline = Date().addingTimeInterval(2)
        while running && Date() < killDeadline { try await Task.sleep(for: .milliseconds(50)) }
        guard !running else { throw BackendFailure(message: "监控进程尚未退出，请稍后重试。") }
        closeHandles()
    }

    private func closeHandles() {
        try? lifetime?.fileHandleForReading.close()
        try? lifetime?.fileHandleForWriting.close()
        try? log?.close()
        lifetime = nil; log = nil; process = nil
    }
}
