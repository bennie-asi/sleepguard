import Foundation

@main enum MonitorLogChecks {
    static func check(_ value: Bool, line: UInt = #line) { if !value { fatalError("Log check failed at line \(line)") } }
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("sleepguard-log-check-\(UUID())")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let now = Date()
        let log = try MonitorLog(directory: directory, days: 7, count: 10, maximumBytes: 8, now: now)
        defer { log.finish() }
        // A single output larger than the limit must split without dropping bytes.
        try log.append(Data("abcdefghijklmnopqrst".utf8), now: now)
        func archives() throws -> [URL] {
            try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("agent-") }
        }
        let first = try archives()
        check(first.count == 2)
        try check(Set(first.map { try String(contentsOf: $0, encoding: .utf8) }) == ["abcdefgh", "ijklmnop"])
        let current = directory.appendingPathComponent("agent.log")
        try check(String(contentsOf: current, encoding: .utf8) == "qrst")
        for url in first + [current] {
            try check((fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        // A date change archives even a small log; no new bytes are required.
        log.configure(days: 7, count: 10, now: now.addingTimeInterval(86400))
        try check(archives().count == 3)
        try check(Data(contentsOf: current).isEmpty)
        // Policy changes prune immediately and preserve the newest archives.
        let all = try archives().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (i, url) in all.enumerated() {
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(Double(i - 3) * 60)], ofItemAtPath: url.path)
        }
        log.configure(days: 7, count: 2, now: now)
        try check(Set(archives()) == Set(all.suffix(2)))
        // Age uses content modification time. Unrelated files and symlinks survive.
        let expired = try archives().first!
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 86400)], ofItemAtPath: expired.path)
        let unrelated = directory.appendingPathComponent("agent-notes.log")
        try Data("keep".utf8).write(to: unrelated)
        let link = directory.appendingPathComponent("agent-1-00000000-0000-0000-0000-000000000000.log")
        try fm.createSymbolicLink(at: link, withDestinationURL: unrelated)
        log.configure(days: 1, count: 2, now: now)
        check(!fm.fileExists(atPath: expired.path))
        try check(String(contentsOf: unrelated, encoding: .utf8) == "keep")
        try check(fm.destinationOfSymbolicLink(atPath: link.path) == unrelated.path)
        try log.append(Data("new".utf8), now: now)
        log.finish()
        // Reopening must append, and keep enforcing the saved limits.
        let reopened = try MonitorLog(directory: directory, days: 1, count: 2, maximumBytes: 8, now: now)
        try reopened.append(Data("er".utf8), now: now)
        reopened.finish()
        try check(String(contentsOf: current, encoding: .utf8) == "newer")
        print("Monitor log checks passed: size/date rotation, live age/count limits, permissions, unrelated files and restart append.")
    }
}
