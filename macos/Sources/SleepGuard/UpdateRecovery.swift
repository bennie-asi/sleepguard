import Foundation

struct UpdateRecovery: Codable {
    let previousBuild: String
    let watcherWasRunning: Bool
    let createdAt: Date
    var continuingUpdate: Bool? = nil

    static var location: URL {
        let root = ProcessInfo.processInfo.environment["SLEEPGUARD_STATE_DIR"]
            ?? NSHomeDirectory() + "/Library/Application Support/sleepguard"
        return URL(fileURLWithPath: root).appendingPathComponent("update-recovery.json")
    }

    func save() throws {
        let directory = Self.location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.location.path)
    }

    static func take() throws -> UpdateRecovery? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        let recovery = try JSONDecoder().decode(UpdateRecovery.self, from: Data(contentsOf: location))
        try FileManager.default.removeItem(at: location)
        return recovery
    }

    static func clear() { try? FileManager.default.removeItem(at: location) }
}
