import Foundation

struct BackendFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
actor GoBackend {
    func manualAction(_ candidate: Candidate, force: Bool) async throws -> ManualResult {
        guard let target = candidate.target else { throw BackendFailure(message: "责任应用未确定。") }
        let data = try encoder.encode(ManualRequest(key: candidate.key, target: target, force: force))
        return try decoder.decode(ManualResult.self, from: await run(["ui", "manual-action"], input: data, timeout: 25))
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
    private func run(_ arguments: [String], input: Data? = nil, timeout: TimeInterval = 12) async throws -> Data {
        try await BackendCommand.run(executable: executable, arguments: arguments + ["--config", configPath, "--state-dir", stateDirectory], input: input, timeout: timeout)
    }
    func configuration() async throws -> ConfigEnvelope {
        let envelope = try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "config"]))
        await applyLogPolicy(envelope.config.monitor)
        return envelope
    }
    func save(_ envelope: ConfigEnvelope) async throws -> ConfigEnvelope {
        let saved = try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "save-config"], input: encoder.encode(envelope)))
        await applyLogPolicy(saved.config.monitor)
        return saved
    }
    private func applyLogPolicy(_ monitor: MonitorConfig) async {
        await AppMonitor.shared.configureLog(days: monitor.logRetentionDays, count: monitor.logRetentionCount)
    }
    func logFailure() async -> String? { await AppMonitor.shared.logFailure }
    func status() async throws -> GuardStatus { try decoder.decode(GuardStatus.self, from: await run(["ui", "status"])) }
    func history(_ query: HistoryQuery) async throws -> HistoryResult { try decoder.decode(HistoryResult.self, from: await run(query.arguments)) }
    func processes() async throws -> [GuardProcess] { try decoder.decode([GuardProcess].self, from: await run(["ui", "processes"], timeout: 25)) }
    func pause(minutes: Int) async throws { _ = try await run(["snooze", "all", "--for", "\(minutes)m"]) }
    func resume() async throws { _ = try await run(["ui", "resume"]) }
    func startMonitor() async throws {
        if await AppMonitor.shared.running { return }
        guard try await !status().watcherRunning else {
            throw BackendFailure(message: "已有其他监控进程正在运行，请先停止该进程。")
        }
        _ = try await configuration()
        try await AppMonitor.shared.start(executable: executable, config: configPath, state: stateDirectory)
    }
    func stopMonitor() async throws { try await AppMonitor.shared.stop() }
    func monitoringRequestedForUpdate() async throws -> Bool {
        let watcherRunning = try await status().watcherRunning
        let requested = await AppMonitor.shared.monitoringRequested
        return watcherRunning || requested
    }
    func startupFailure() async -> String {
        if let failure = await AppMonitor.shared.failure { return failure }
        return "监控未能启动，请在历史页查看运行日志。"
    }
    func testChannel(_ id: String) async throws -> Delivery { try decoder.decode(Delivery.self, from: await run(["ui", "test-notification", "--channel", id], timeout: 75)) }
}
