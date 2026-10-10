import AppKit
import SwiftUI
import UserNotifications

@MainActor final class GuardModel: ObservableObject {
    let backend = GoBackend()
    let screenController = ScreenController()
    let shortcuts = ShortcutController()
    private var blackoutTask: Task<Void, Never>?
    func blackout() async {
        guard !screenController.active, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await backend.blackoutHold("begin")
            try screenController.blackout { [weak self] in
                guard let self else { return }
                self.blackoutTask?.cancel(); self.blackoutTask = nil
                Task { do { try await self.backend.blackoutHold("end"); await self.refresh() } catch { self.error = error.localizedDescription } }
            }
            blackoutTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)); try Task.checkCancellation(); try await self?.backend.blackoutHold("renew") }
                    catch { if !Task.isCancelled { self?.screenController.restore(); self?.error = "黑屏保护连接中断，已恢复屏幕。" }; break }
                }
            }
        } catch {
            screenController.restore()
            try? await backend.blackoutHold("end")
            self.error = error.localizedDescription
        }
    }
    func lockScreen() {
        screenController.restore()
        do { try ScreenController.lockScreen() } catch { self.error = error.localizedDescription }
    }
    func confirmManualAction(_ candidate: Candidate, force: Bool) {
        guard !busy, let target = candidate.target, !target.protected else { return }
        let alert = NSAlert()
        alert.messageText = force ? "强制结束 \(candidate.label)？" : "结束 \(candidate.label)？"
        alert.informativeText = "\(target.bundleId ?? target.path)\nPID \(target.pid)\n" + (force ? "未保存的内容可能丢失。" : "将请求应用退出；无响应时不会自动强制结束。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: force ? "强制结束" : "结束应用")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        Task {
            defer { busy = false }
            do { let result = try await backend.manualAction(candidate, force: force); information = result.message; await refresh(); await reloadHistory() }
            catch { self.error = error.localizedDescription }
        }
    }
    @Published var status: GuardStatus?
    @Published var configuration: GuardConfig?
    @Published var rules: [AppRule] = []
    @Published var autoActions = false
    @Published var monitor: MonitorConfig?
    @Published var actions: ActionConfig?
    @Published var events: [HistoryEvent] = []
    @Published var catalog: [CatalogApp] = []
    @Published var catalogLoading = false
    @Published var busy = false
    @Published var error: String?
    @Published var information: String? {
        didSet {
            informationTask?.cancel()
            guard information != nil else { return }
            informationTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                self?.information = nil
            }
        }
    }
    @Published private(set) var serviceOperation: ServiceOperation?
    @Published private(set) var refreshing = false
    @Published private(set) var refreshingHistory = false
    @Published private(set) var quitting = false
    @Published var permission: UNAuthorizationStatus = .notDetermined
    @Published var channelResults: [String: Delivery] = [:]
    @Published var tab: ManagementTab = .status
    private var timerTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var informationTask: Task<Void, Never>?
    private var savedRules: [AppRule] = []
    private var savedAutoActions = false
    private var savedMonitor: MonitorConfig?
    private var savedActions: ActionConfig?
    private var started = false

    var dirtyRules: Bool { rules != savedRules || autoActions != savedAutoActions }
    var dirtySettings: Bool { monitor != savedMonitor || actions != savedActions }
    var settingsValidation: String? {
        guard let monitor, let actions else { return nil }
        for (title, value, minimum) in [
            ("检查间隔", monitor.interval, 1.0), ("额外等待时间", monitor.grace, 0),
            ("唤醒宽限期", monitor.wakeGrace, 0), ("通知间隔", monitor.reminderInterval, 0),
            ("处理等待", actions.wait, 0), ("退出前等待", monitor.finalGrace, 0),
            ("请求退出后等待", actions.killAfter, 0)
        ] {
            if let message = DurationValue.validation(value, minimum: minimum) { return title + "：" + message }
        }
        return nil
    }
    var channels: [NotificationChannel] { configuration?.channels ?? [] }
    var systemEnabled: Bool { configuration?.notifications.systemEnabled ?? false }
    var enabledChannels: Int { (systemEnabled ? 1 : 0) + channels.filter { $0.enabled && $0.ready }.count }
    var permissionText: String {
        switch permission { case .authorized, .provisional: "已授权"; case .denied: "权限已关闭"; default: "尚未授权" }
    }
    var menuSymbol: String { status?.watcherRunning != true ? "moon.zzz" : status?.paused == true ? "pause.circle" : status?.assessment.eligible == true ? "exclamationmark.circle" : "moon.stars" }
    var headline: String {
        guard let status else { return "正在读取状态…" }
        if let serviceOperation { return serviceOperation.title }
        if !status.watcherRunning { return "后台服务未运行" }
        if status.paused { return "提醒与处理已暂停" }
        return status.assessment.eligible ? "\(status.assessment.candidates.count) 个应用需要关注" : "暂未发现休眠异常"
    }
    var historyGroups: [HistoryGroup] {
        var groups: [HistoryGroup] = [], indices: [String: Int] = [:]
        for event in events {
            let key = event.delivery?.roundId ?? "event-\(event.id)"
            if let index = indices[key] { groups[index].events.append(event) }
            else { indices[key] = groups.count; groups.append(HistoryGroup(events: [event])) }
        }
        return groups
    }
    func start() async {
        guard !started else { return }; started = true
        shortcuts.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .blackout: if self.screenController.active { self.screenController.restore() } else { Task { await self.blackout() } }
            case .lock: self.lockScreen()
            case .open: NotificationCenter.default.post(name: .sleepGuardShowWindow, object: nil)
            }
        }
        shortcuts.load()
        do {
            let envelope = try await backend.configuration()
            load(envelope.config, resetRules: true, resetSettings: true)
        } catch { self.error = error.localizedDescription }
        await refresh()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                await self?.refresh()
            }
        }
    }
    private func load(_ config: GuardConfig, resetRules: Bool = false, resetSettings: Bool = false) {
        configuration = config
        if resetRules { rules = config.rules; autoActions = config.actions.enabled; savedRules = rules; savedAutoActions = autoActions }
        if resetSettings { monitor = config.monitor; actions = config.actions; savedMonitor = monitor; savedActions = actions }
    }
    func refresh(userInitiated: Bool = false) async {
        guard !refreshing, serviceOperation == nil, !quitting else { return }; refreshing = true; defer { refreshing = false }
        do {
            status = try await backend.status()
            let envelope = try await backend.configuration()
            load(envelope.config, resetRules: !dirtyRules, resetSettings: !dirtySettings)
            if tab == .history { await reloadHistory() }
            if userInitiated { information = "状态已更新。" }
        } catch { self.error = error.localizedDescription }
        // Permission lookup must not hold the status refresh gate while waiting for macOS.
        if permissionTask == nil {
            permissionTask = Task { [weak self] in
                let authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                self?.permission = authorization
                self?.permissionTask = nil
            }
        }
    }
    func reloadHistory() async {
        guard !refreshingHistory, !quitting else { return }; refreshingHistory = true; defer { refreshingHistory = false }
        do { events = try await backend.history() } catch { self.error = error.localizedDescription }
    }
    func prepareCatalog() async {
        guard !catalogLoading else { return }; catalogLoading = true; defer { catalogLoading = false }
        do { catalog = await AppCatalog.collect(processes: try await backend.processes()) }
        catch { catalog = await AppCatalog.collect(processes: []); self.error = error.localizedDescription }
    }
    // Each save changes only its own page; draft rules/settings cannot be saved by a channel toggle.
    private func update(resetRules: Bool = false, resetSettings: Bool = false, _ mutation: (inout GuardConfig) throws -> Void) async throws {
        var envelope = try await backend.configuration()
        try mutation(&envelope.config)
        let saved = try await backend.save(envelope)
        load(saved.config, resetRules: resetRules, resetSettings: resetSettings)
        information = status?.watcherRunning == true ? "已保存；后台将在下一次采样时应用。" : "已保存，启动后台后生效。"
    }
    func saveRules() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let rules = self.rules, enabled = autoActions
        do { try await update(resetRules: true) { $0.rules = rules; $0.actions.enabled = enabled }; await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func discardRules() { rules = savedRules; autoActions = savedAutoActions }
    func discardSettings() { monitor = savedMonitor; actions = savedActions }
    func saveSettings() async {
        guard !busy, let monitor, let actions else { return }; busy = true; defer { busy = false }
        if let message = settingsValidation { error = message; return }
        do { try await update(resetSettings: true) { $0.monitor = monitor; $0.actions.wait = actions.wait; $0.actions.killAfter = actions.killAfter; $0.actions.allowSigkill = actions.allowSigkill }; await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func setSystemNotifications(_ enabled: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if enabled {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard allowed else { throw BackendFailure(message: "系统通知尚未允许。请在 macOS 设置中开启 SleepGuard 通知权限。") }
                permission = .authorized
            }
            try await update { $0.notifications.systemEnabled = enabled }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func setChannel(_ channel: NotificationChannel, enabled: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await update { config in
                guard let index = config.channels.firstIndex(where: { $0.id == channel.id }) else { throw BackendFailure(message: "此渠道已被移除，请刷新后重试。") }
                config.channels[index].enabled = enabled
            }
        } catch { self.error = error.localizedDescription }
    }
    func saveChannel(_ channel: NotificationChannel, token: String) async throws {
        guard !busy else { throw BackendFailure(message: "正在保存，请稍后重试。") }; busy = true; defer { busy = false }
        if channel.ready && !token.isEmpty { try Keychain.save(token, service: channel.keychainService) }
        try await update { config in
            if let index = config.channels.firstIndex(where: { $0.id == channel.id }) { config.channels[index] = channel }
            else { config.channels.append(channel) }
        }
        channelResults[channel.id] = nil
    }
    func deleteChannel(_ channel: NotificationChannel) async throws {
        guard !busy else { return }; busy = true; defer { busy = false }
        try await update { $0.channels.removeAll { $0.id == channel.id } }
        channelResults[channel.id] = nil
    }
    func testChannel(_ id: String) async {
        // Tests have their own task and result; they do not disable or change another channel.
        do {
            if let channel = channels.first(where: { $0.id == id }), !channel.keychainService.isEmpty, channel.tokenEnv.isEmpty {
                _ = try Keychain.read(service: channel.keychainService, interactive: true)
            }
            channelResults[id] = try await backend.testChannel(id); await reloadHistory()
        }
        catch { channelResults[id] = Delivery(channelId: id, channelName: id == "system" ? "系统通知" : channels.first(where: { $0.id == id })?.name ?? id, provider: "", roundId: "", success: false, message: error.localizedDescription) }
    }
    func pause(minutes: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await backend.pause(minutes: minutes); information = "已暂停 \(minutes) 分钟，仍继续采样。"; await refresh(); await reloadHistory() }
        catch { self.error = error.localizedDescription }
    }
    func resume() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await backend.resume(); information = "已恢复通知与处理，重新累计异常。"; await refresh(); await reloadHistory() }
        catch { self.error = error.localizedDescription }
    }
    func startService() async {
        guard !busy else { return }; busy = true; serviceOperation = .starting
        information = nil
        defer { busy = false; serviceOperation = nil }
        do {
            // Create a default config only if it is absent; do not apply any unsaved rule drafts.
            let envelope = try await backend.configuration()
            if envelope.revision.isEmpty { _ = try await backend.save(envelope) }
            try await backend.startService()
            try await confirmService(running: true)
            information = "后台已启动，关闭窗口后仍会监控。"
        } catch { self.error = error.localizedDescription }
    }
    func stopService() async {
        guard !busy else { return }; busy = true; serviceOperation = .stopping
        information = nil
        defer { busy = false; serviceOperation = nil }
        do { try await backend.stopService(); try await confirmService(running: false); information = "后台已停止。" }
        catch { self.error = error.localizedDescription }
    }
    func stopForQuit() async throws {
        screenController.restore()
        guard !busy else { throw BackendFailure(message: "正在完成其他操作，请稍后退出。") }
        busy = true; quitting = true; serviceOperation = .stopping; information = nil
        defer { busy = false; quitting = false; serviceOperation = nil }
        try await backend.stopService()
        try await confirmService(running: false)
        timerTask?.cancel()
    }
    private func confirmService(running: Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            let latest = try await backend.status()
            status = latest
            if latest.watcherRunning == running { return }
            try await Task.sleep(for: .milliseconds(300))
        } while Date() < deadline
        throw BackendFailure(message: running ? "未确认后台运行，请在历史页查看运行日志。" : "仍检测到监控进程，请刷新状态或查看运行日志。")
    }
}

enum ServiceOperation {
    case starting, stopping
    var title: String { self == .starting ? "正在启动后台…" : "正在停止后台…" }
}
