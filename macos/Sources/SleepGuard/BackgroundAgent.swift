import AppKit
import ServiceManagement
import Security

// Register the bundled agent as part of SleepGuard so Login Items uses the app's identity.
@MainActor enum BackgroundAgent {
    static var service: SMAppService { .agent(plistName: "io.sleepguard.app.agent.plist") }
    static var requiresApproval: Bool { service.status == .requiresApproval }
    static func isAdHocSigned() throws -> Bool {
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code,
              SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let flags = (information as? [String: Any])?[kSecCodeInfoFlags as String] as? NSNumber else {
            throw BackendFailure(message: "无法确认应用签名，请重新安装 SleepGuard。")
        }
        return flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0
    }
    static func stop() async throws {
        // The original agent label may still have a legacy record in macOS's cache.
        for (label, agent) in [("io.sleepguard.app.agent", service), ("io.sleepguard.agent", SMAppService.agent(plistName: "io.sleepguard.agent.plist"))] {
            if agent.status == .enabled || agent.status == .requiresApproval {
                // The compatibility label can also belong to a plain LaunchAgent.
                // SMAppService.status calls that enabled too, but cannot unregister it.
                let output = try? await BackendCommand.run(executable: URL(fileURLWithPath: "/bin/launchctl"), arguments: ["print", "gui/\(getuid())/\(label)"], timeout: 3)
                let managed = output.map { String(decoding: $0, as: UTF8.self).contains("managed_by = com.apple.xpc.ServiceManagement") } ?? false
                if (output != nil || label == "io.sleepguard.agent") && !managed { continue }
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
