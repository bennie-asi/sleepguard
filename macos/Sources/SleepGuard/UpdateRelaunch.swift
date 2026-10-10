import AppKit
import Darwin
import Foundation

// A running executable that was unlinked cannot obtain an AuthorizationRef.
// Re-enter through the current, signed bundle before asking Sparkle to install.
@MainActor enum UpdateRelaunch {
    static let helperArgument = "--update-relaunch-helper"
    static let resumeArgument = "--resume-update"
    static let recoveryArgument = "--recover-running-copy"

    static var executableIsCurrent: Bool {
        var path = [UInt8](repeating: 0, count: 4096)
        guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0,
              let executable = Bundle.main.executableURL else { return false }
        let actual = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }, as: UTF8.self)).resolvingSymlinksInPath()
        return actual.standardizedFileURL == executable.resolvingSymlinksInPath().standardizedFileURL
    }

    static func prepareHelper() async throws {
        guard let executable = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw BackendFailure(message: "当前应用文件已移除，无法自动重新启动。")
        }
        let directory = UpdateRecovery.location.deletingLastPathComponent()
            .appendingPathComponent("update-relaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let ready = directory.appendingPathComponent("ready")
        let child = Process()
        child.executableURL = executable
        child.arguments = [helperArgument, String(getpid()), ready.path]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline && child.isRunning {
                if FileManager.default.fileExists(atPath: ready.path) { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            if child.isRunning { child.terminate() }
            throw BackendFailure(message: "重新启动更新器失败，请重试。")
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func runHelper(arguments: [String]) async -> Int32 {
        guard arguments.count == 2, let parent = Int32(arguments[0]), parent > 1,
              parent == getppid(), executableIsCurrent else { return 2 }
        let ready = URL(fileURLWithPath: arguments[1])
        let root = UpdateRecovery.location.deletingLastPathComponent().standardizedFileURL
        guard ready.lastPathComponent == "ready",
              ready.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == root,
              ready.deletingLastPathComponent().lastPathComponent.hasPrefix("update-relaunch-") else { return 2 }
        defer { try? FileManager.default.removeItem(at: ready.deletingLastPathComponent()) }
        do {
            try Data().write(to: ready, options: .atomic)
            let deadline = Date().addingTimeInterval(30)
            while kill(parent, 0) == 0 {
                guard Date() < deadline else { return 3 }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard errno == ESRCH else { return 3 }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--show-window", resumeArgument]
            configuration.environment = ProcessInfo.processInfo.environment
            let result: Int32 = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil ? 0 : 4)
                }
            }
            return result
        } catch { return 4 }
    }

    // Maintenance entry for pre-fix builds whose executable is already unlinked.
    // It only retires this user's obsolete copy of this same application.
    static func recoverRunningCopy(arguments: [String]) async -> Int32 {
        guard (1...2).contains(arguments.count), executableIsCurrent,
              let identifier = Bundle.main.bundleIdentifier else { return 2 }
        let oldBundle = URL(fileURLWithPath: arguments[0]).resolvingSymlinksInPath()
        let destination = arguments.count == 2 ? URL(fileURLWithPath: arguments[1]).resolvingSymlinksInPath() : Bundle.main.bundleURL
        guard oldBundle != Bundle.main.bundleURL.resolvingSymlinksInPath(),
              let bundle = Bundle(url: oldBundle), bundle.bundleIdentifier == identifier,
              let installed = Bundle(url: destination), installed.bundleIdentifier == identifier,
              installed.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return 2 }
        let obsolete = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter {
            $0.processIdentifier != getpid() && $0.bundleURL?.resolvingSymlinksInPath() == oldBundle
        }
        guard obsolete.count == 1, let application = obsolete.first else { return 2 }
        let pid = application.processIdentifier
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) > 0,
              info.pbi_uid == getuid() else { return 2 }
        var path = [UInt8](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) == 0, errno == ENOENT else { return 2 }
        let model = GuardModel()
        do {
            _ = try await BackendCommand.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                                             arguments: ["--verify", "--deep", "--strict", destination.path], timeout: 10)
            try await model.prepareForUpdate()
            if let state = try UpdateRecovery.take() {
                try UpdateRecovery(previousBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                                   watcherWasRunning: state.watcherWasRunning, createdAt: state.createdAt).save()
            }
            var current = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &current, Int32(MemoryLayout.size(ofValue: current))) > 0,
                  current.pbi_start_tvsec == info.pbi_start_tvsec,
                  current.pbi_start_tvusec == info.pbi_start_tvusec,
                  kill(pid, SIGTERM) == 0 else {
                throw BackendFailure(message: "旧进程身份已变化，停止恢复。")
            }
            let deadline = Date().addingTimeInterval(10)
            while kill(pid, 0) == 0 {
                guard Date() < deadline else { throw BackendFailure(message: "旧进程未退出，恢复已停止。") }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard errno == ESRCH else { throw BackendFailure(message: "无法确认旧进程已退出。") }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--show-window"]
            let result: Int32 = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil ? 0 : 4)
                }
            }
            if result != 0 { await model.restoreAfterFailedUpdate() }
            return result
        } catch {
            await model.restoreAfterFailedUpdate()
            FileHandle.standardError.write(Data("SleepGuard update recovery failed: \(error.localizedDescription)\n".utf8))
            return 4
        }
    }
}
