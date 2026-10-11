import Foundation
import Darwin

// Only this object owns the output file. The child writes to a pipe, so renaming
// a log never leaves it writing to an old (or already deleted) archive inode.
// FileHandle callbacks and the main-actor supervisor serialize through the lock.
final class MonitorLog: @unchecked Sendable {
    let pipe = Pipe()
    private let lock = NSLock()
    private let directory: URL
    private let maximumBytes: Int
    private var output: FileHandle?
    private var size = 0
    private var openedAt: Date
    private var days: Int
    private var count: Int
    private var finished = false
    private var lastMaintenance: Date
    private var errorMessage: String?
    var failure: String? { lock.withLock { errorMessage } }
    private var current: URL { directory.appendingPathComponent("agent.log") }

    init(directory: URL, days: Int, count: Int, maximumBytes: Int = 10 * 1024 * 1024, now: Date = Date()) throws {
        self.directory = directory; self.days = days; self.count = count
        self.maximumBytes = maximumBytes; openedAt = now; lastMaintenance = now
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try open(now: now)
        try maintain(now: now)
    }

    // Call after Process.run, including its failure path, to drop the parent's
    // write end. EOF then means all child output has been consumed.
    func capture() {
        try? pipe.fileHandleForWriting.close()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] _ in self?.receive() }
    }

    private func receive() {
        lock.withLock {
            guard !finished else { return }
            do {
                guard let data = try readAvailable() else { return }
                if data.isEmpty { pipe.fileHandleForReading.readabilityHandler = nil; return }
                try appendLocked(data, now: Date())
            } catch { errorMessage = "运行日志写入失败：\(error.localizedDescription)" }
        }
    }

    // Foundation's read(upToCount:) can wait for the requested size on a pipe.
    // A nonblocking POSIX read consumes only available bytes, so a quiet child
    // never holds the lock while the main actor is checking or configuring logs.
    // nil means no data yet; empty Data means EOF. Caller holds lock.
    private func readAvailable() throws -> Data? {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let length = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if length >= 0 { return Data(bytes.prefix(length)) }
            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func append(_ data: Data, now: Date = Date()) throws {
        try lock.withLock { try appendLocked(data, now: now) }
    }

    private func appendLocked(_ data: Data, now: Date) throws {
        guard !finished else { return }
        if output == nil { try open(now: now) }
        if size > 0 && !Calendar.current.isDate(openedAt, inSameDayAs: now) { try rotate(now: now) }
        var offset = 0
        while offset < data.count {
            if size >= maximumBytes { try rotate(now: now) }
            let length = min(maximumBytes - size, data.count - offset)
            try output?.write(contentsOf: data.subdata(in: offset..<(offset + length)))
            size += length; offset += length
        }
    }

    func configure(days: Int, count: Int, now: Date = Date()) {
        lock.withLock {
            guard !finished else { return }
            let changed = self.days != days || self.count != count
            self.days = days; self.count = count
            guard changed || now.timeIntervalSince(lastMaintenance) >= 60 else { return }
            do { try maintain(now: now); errorMessage = nil }
            catch { errorMessage = "运行日志轮转失败：\(error.localizedDescription)" }
        }
    }

    // The caller waits for child exit first. Drain its final stdout/stderr before
    // closing, including errors emitted just before an automatic restart.
    func finish() {
        lock.withLock {
            guard !finished else { return }
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForWriting.close()
            do {
                while let data = try readAvailable(), !data.isEmpty {
                    try appendLocked(data, now: Date())
                }
            } catch { errorMessage = "运行日志收尾失败：\(error.localizedDescription)" }
            finished = true
            try? pipe.fileHandleForReading.close()
            try? output?.close(); output = nil
        }
    }

    private func open(now: Date) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: current.path) {
            guard fm.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let attributes = try fm.attributesOfItem(atPath: current.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileWriteInvalidFileName) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
        output = try FileHandle(forWritingTo: current)
        size = Int(try output!.seekToEnd())
        openedAt = attributes[.creationDate] as? Date ?? attributes[.modificationDate] as? Date ?? now
        if size == 0 { openedAt = now }
    }

    private func rotate(now: Date) throws {
        try output?.close(); output = nil
        // Timestamp plus UUID prevents collisions on rapid restart/size rotation.
        let archive = directory.appendingPathComponent("agent-\(Int64(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased()).log")
        try FileManager.default.moveItem(at: current, to: archive)
        // Age reflects when the last bytes were written, including pre-upgrade logs.
        try open(now: now)
        try prune(now: now)
    }

    private func maintain(now: Date) throws {
        if size > 0 && (size >= maximumBytes || !Calendar.current.isDate(openedAt, inSameDayAs: now)) {
            try rotate(now: now)
        } else { try prune(now: now) }
        lastMaintenance = now
    }

    private func prune(now: Date) throws {
        let fm = FileManager.default
        let pattern = #"^agent-[0-9]+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.log$"#
        var archives: [(URL, Date)] = []
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil else { continue }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let modified = attributes[.modificationDate] as? Date else { continue }
            archives.append((url, modified))
        }
        archives.sort { $0.1 == $1.1 ? $0.0.lastPathComponent > $1.0.lastPathComponent : $0.1 > $1.1 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        for (index, archive) in archives.enumerated() where index >= count || archive.1 < cutoff {
            try fm.removeItem(at: archive.0)
        }
    }
}
