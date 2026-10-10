import AppKit
import ServiceManagement
import Darwin

struct AgentSettings: Codable {
    let configPath: String
    let stateDirectory: String
    static var location: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/sleepguard/agent-settings.json")
    }
}

// Register the bundled agent as part of SleepGuard so Login Items uses the app's identity.
@MainActor enum BackgroundAgent {
    static var service: SMAppService { .agent(plistName: "io.sleepguard.app.agent.plist") }
    static func stop() async throws {
        // The original agent label may still have a legacy record in macOS's cache.
        for agent in [service, SMAppService.agent(plistName: "io.sleepguard.agent.plist")] {
            if agent.status == .enabled || agent.status == .requiresApproval {
                // Keep SMAppService on the main actor. Older SDKs do not mark it
                // Sendable, so their imported async method cannot cross actors.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    agent.unregister(completionHandler: { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    })
                }
            }
        }
    }
    static func start(configPath: String, stateDirectory: String) async throws {
        try await stop()
        let manager = FileManager.default
        try manager.createDirectory(atPath: stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.createDirectory(at: AgentSettings.location.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let settings = AgentSettings(configPath: configPath, stateDirectory: stateDirectory)
        try JSONEncoder().encode(settings).write(to: AgentSettings.location, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AgentSettings.location.path)
        try service.register()
        if service.status == .requiresApproval {
            throw BackendFailure(message: "请在系统设置 → 通用 → 登录项中允许 SleepGuard 在后台运行，然后重新启动后台。")
        }
    }
}

enum MonitorHelper {
    static func run() -> Int32 {
        guard let executable = Bundle.main.url(forResource: "sleepguard", withExtension: nil) else { return 70 }
        var monitorArguments = Array(CommandLine.arguments.dropFirst(2))
        if monitorArguments.isEmpty {
            do {
                let settings = try JSONDecoder().decode(AgentSettings.self, from: Data(contentsOf: AgentSettings.location))
                let log = settings.stateDirectory + "/agent.log"
                let descriptor = log.withCString { open($0, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR) }
                guard descriptor >= 0 else { throw BackendFailure(message: "无法打开后台日志。") }
                guard dup2(descriptor, STDERR_FILENO) >= 0 else { close(descriptor); return 71 }
                close(descriptor)
                monitorArguments = ["watch", "--config", settings.configPath, "--state-dir", settings.stateDirectory]
            } catch {
                FileHandle.standardError.write(Data("SleepGuard: \(error.localizedDescription)\n".utf8))
                return 70
            }
        }
        let arguments = [executable.path] + monitorArguments
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers = strings + [nil]
        _ = executable.path.withCString { execv($0, &pointers) }
        let code = errno
        FileHandle.standardError.write(Data("SleepGuard could not start the Go monitor: \(String(cString: strerror(code)))\n".utf8))
        return 71
    }
}
