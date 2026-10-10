import Foundation

struct BackendFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
actor GoBackend {
    func manualAction(_ candidate: Candidate, force: Bool) async throws -> ManualResult {
        guard let target = candidate.target else { throw BackendFailure(message: "责任应用未确定。") }
        let data = try encoder.encode(ManualRequest(key: candidate.key, target: target, force: force))
        return try decoder.decode(ManualResult.self, from: await run(["ui", "manual-action"], input: data))
    }
    func blackoutHold(_ operation: String) async throws { _ = try await run(["ui", "blackout-hold", operation]) }
    let executable: URL
    let configPath: String
    let stateDirectory: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let environment = ProcessInfo.processInfo.environment
        executable = environment["SLEEPGUARD_BACKEND"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("sleepguard")
        configPath = environment["SLEEPGUARD_CONFIG"] ?? NSHomeDirectory() + "/.config/sleepguard/config.toml"
        stateDirectory = environment["SLEEPGUARD_STATE_DIR"] ?? NSHomeDirectory() + "/Library/Application Support/sleepguard"
        encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    // Commands run off the main thread. Output goes to private temporary files to avoid pipe deadlocks.
    private func run(_ arguments: [String], input: Data? = nil, timeout: TimeInterval = 35) async throws -> Data {
        let executable = self.executable, configPath = self.configPath, stateDirectory = self.stateDirectory
        return try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = executable
            task.arguments = arguments + ["--config", configPath, "--state-dir", stateDirectory]
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleepguard-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("stdout"), errorURL = directory.appendingPathComponent("stderr"), inputURL = directory.appendingPathComponent("stdin")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try (input ?? Data()).write(to: inputURL, options: .atomic)
            let output = try FileHandle(forWritingTo: outputURL), errors = try FileHandle(forWritingTo: errorURL), stdin = try FileHandle(forReadingFrom: inputURL)
            defer { try? output.close(); try? errors.close(); try? stdin.close() }
            task.standardOutput = output; task.standardError = errors; task.standardInput = stdin
            try task.run()
            let deadline = Date().addingTimeInterval(timeout)
            while task.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(40)) }
            if task.isRunning {
                task.terminate()
                let shutdownDeadline = Date().addingTimeInterval(2)
                while task.isRunning && Date() < shutdownDeadline { try await Task.sleep(for: .milliseconds(40)) }
                if task.isRunning { _ = Darwin.kill(task.processIdentifier, SIGKILL) }
                task.waitUntilExit()
                throw BackendFailure(message: "后台命令超时，请刷新后重试。")
            }
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                let message = (try? String(contentsOf: errorURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw BackendFailure(message: message?.isEmpty == false ? message! : "后台命令执行失败。")
            }
            return try Data(contentsOf: outputURL)
        }.value
    }
    func configuration() async throws -> ConfigEnvelope { try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "config"])) }
    func save(_ envelope: ConfigEnvelope) async throws -> ConfigEnvelope { try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "save-config"], input: encoder.encode(envelope))) }
    func status() async throws -> GuardStatus { try decoder.decode(GuardStatus.self, from: await run(["ui", "status"])) }
    func history() async throws -> [HistoryEvent] { try decoder.decode([HistoryEvent].self, from: await run(["history", "--limit", "100"])) }
    func processes() async throws -> [GuardProcess] { try decoder.decode([GuardProcess].self, from: await run(["ui", "processes"])) }
    func pause(minutes: Int) async throws { _ = try await run(["snooze", "all", "--for", "\(minutes)m"]) }
    func resume() async throws { _ = try await run(["ui", "resume"]) }
    private var bundled: Bool { executable == Bundle.main.resourceURL?.appendingPathComponent("sleepguard") }
    func startService() async throws {
        guard bundled else { _ = try await run(["service", "start"]); return }
        try await BackgroundAgent.stop()
        _ = try await run(["service", "stop"])
        let legacy = NSHomeDirectory() + "/Library/LaunchAgents/io.sleepguard.agent.plist"
        if FileManager.default.fileExists(atPath: legacy) { _ = try await run(["service", "uninstall"]) }
        try await BackgroundAgent.start(configPath: configPath, stateDirectory: stateDirectory)
    }
    func stopService() async throws {
        if bundled { try await BackgroundAgent.stop() }
        _ = try await run(["service", "stop"])
    }
    func testChannel(_ id: String) async throws -> Delivery { try decoder.decode(Delivery.self, from: await run(["ui", "test-notification", "--channel", id], timeout: 75)) }
}
