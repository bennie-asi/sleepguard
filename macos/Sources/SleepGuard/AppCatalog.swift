import AppKit
import Foundation

@MainActor enum AppCatalog {
    static func protectedPath(_ path: String, bundleId: String = "") -> Bool {
        bundleId == "io.sleepguard.app" || ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains(where: path.hasPrefix)
    }
    static func collect(processes: [GuardProcess]) async -> [CatalogApp] {
        var result: [CatalogApp] = []
        var identities = Set<String>(), representedPIDs = Set<Int32>()
        let inspected = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        for app in NSWorkspace.shared.runningApplications {
            guard let executable = app.executableURL else { continue }
            let bundleId = app.bundleIdentifier ?? "", path = executable.resolvingSymlinksInPath().path
            let identity = bundleId.isEmpty ? path : bundleId
            representedPIDs.insert(app.processIdentifier)
            if !identities.insert(identity).inserted { continue }
            result.append(CatalogApp(id: identity, name: app.localizedName ?? executable.lastPathComponent, bundleId: bundleId, path: path, appPath: app.bundleURL?.path ?? path, pid: app.processIdentifier, group: app.activationPolicy == .regular ? "已启动" : "后台任务", protected: inspected[app.processIdentifier]?.protected ?? protectedPath(path, bundleId: bundleId)))
        }
        for process in processes where !representedPIDs.contains(process.pid) {
            guard process.uid == getuid() || ["coreaudiod", "runningboardd", "powerd"].contains(process.name) else { continue }
            let bundleId = process.bundleId ?? "", identity = bundleId.isEmpty ? process.path : bundleId
            guard identities.insert(identity).inserted else { continue }
            result.append(CatalogApp(id: identity, name: process.name, bundleId: bundleId, path: process.path, appPath: process.path, pid: process.pid, group: "后台任务", protected: process.protected))
        }
        let installed = await Task.detached { installedApplications() }.value
        for app in installed where identities.insert(app.id).inserted { result.append(app) }
        return result.sorted { lhs, rhs in
            let order = ["已启动": 0, "后台任务": 1, "未启动": 2]
            if lhs.group != rhs.group { return order[lhs.group, default: 3] < order[rhs.group, default: 3] }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    nonisolated private static func installedApplications() -> [CatalogApp] {
        let directories = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var result: [CatalogApp] = []
        for directory in directories {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension == "app" {
                files.skipDescendants()
                guard let bundle = Bundle(url: url), let executable = bundle.executableURL else { continue }
                let bundleId = bundle.bundleIdentifier ?? "", path = executable.resolvingSymlinksInPath().path
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
                result.append(CatalogApp(id: bundleId.isEmpty ? path : bundleId, name: name, bundleId: bundleId, path: path, appPath: url.path, pid: nil, group: "未启动", protected: bundleId == "io.sleepguard.app" || path.hasPrefix("/System/")))
            }
        }
        return result
    }
}
