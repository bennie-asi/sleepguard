import Foundation

struct UpdateRecovery: Codable {
    let previousBuild: String
    let watcherWasRunning: Bool
    let createdAt: Date

    static var location: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/sleepguard/update-recovery.json")
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
