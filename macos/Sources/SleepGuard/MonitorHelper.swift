import Foundation
import Darwin

struct AgentSettings: Codable {
    let configPath: String
    let stateDirectory: String
    static var location: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/sleepguard/agent-settings.json")
    }
}

enum MonitorHelper {
    static func run(arguments: [String]) -> Int32 {
        // Resolve the containing app for both the dedicated helper and the legacy entry point.
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return 70 }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let contents = URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let executable = contents.appendingPathComponent("Resources/sleepguard")
        var monitorArguments = arguments
        if monitorArguments.isEmpty {
            do {
                let settings = try JSONDecoder().decode(AgentSettings.self, from: Data(contentsOf: AgentSettings.location))
                let log = settings.stateDirectory + "/agent.log"
                let descriptor = log.withCString { open($0, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR) }
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                guard dup2(descriptor, STDERR_FILENO) >= 0 else { close(descriptor); return 71 }
                close(descriptor)
                monitorArguments = ["watch", "--config", settings.configPath, "--state-dir", settings.stateDirectory]
            } catch {
                FileHandle.standardError.write(Data("SleepGuard: \(error.localizedDescription)\n".utf8))
                return 70
            }
        }
        let strings = ([executable.path] + monitorArguments).map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers = strings + [nil]
        _ = executable.path.withCString { execv($0, &pointers) }
        let code = errno
        FileHandle.standardError.write(Data("SleepGuard could not start the Go monitor: \(String(cString: strerror(code)))\n".utf8))
        return 71
    }
}
