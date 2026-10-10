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
    func configuration() async throws -> ConfigEnvelope { try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "config"])) }
    func save(_ envelope: ConfigEnvelope) async throws -> ConfigEnvelope { try decoder.decode(ConfigEnvelope.self, from: await run(["ui", "save-config"], input: encoder.encode(envelope))) }
    func status() async throws -> GuardStatus { try decoder.decode(GuardStatus.self, from: await run(["ui", "status"])) }
    func history() async throws -> [HistoryEvent] { try decoder.decode([HistoryEvent].self, from: await run(["history", "--limit", "100"])) }
    func processes() async throws -> [GuardProcess] { try decoder.decode([GuardProcess].self, from: await run(["ui", "processes"], timeout: 25)) }
    func pause(minutes: Int) async throws { _ = try await run(["snooze", "all", "--for", "\(minutes)m"]) }
    func resume() async throws { _ = try await run(["ui", "resume"]) }
    private var bundled: Bool { executable == Bundle.main.resourceURL?.appendingPathComponent("sleepguard") }
    func startService() async throws {
        guard bundled else { _ = try await run(["service", "start"]); return }
        try await BackgroundAgent.stop()
        _ = try await run(["service", "stop"], timeout: 20)
        let legacy = NSHomeDirectory() + "/Library/LaunchAgents/io.sleepguard.agent.plist"
        if FileManager.default.fileExists(atPath: legacy) { _ = try await run(["service", "uninstall"]) }
        try await BackgroundAgent.start(configPath: configPath, stateDirectory: stateDirectory)
    }
    func stopService() async throws {
        if bundled { try await BackgroundAgent.stop() }
        _ = try await run(["service", "stop"], timeout: 20)
    }
    func testChannel(_ id: String) async throws -> Delivery { try decoder.decode(Delivery.self, from: await run(["ui", "test-notification", "--channel", id], timeout: 75)) }
}
