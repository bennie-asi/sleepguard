import AppKit
import SwiftUI
import UserNotifications

@MainActor final class GuardModel: ObservableObject {
    @Published private(set) var logFailure: String?
    let backend = GoBackend()
    let screenController = ScreenController()
    let shortcuts = ShortcutController()
    let loginItem: LoginItemController
    let updater = UpdateController.shared
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
    let history: HistoryModel
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
    @Published private var dismissedWatcherErrorAt = ""
    @Published private(set) var monitorOperation: MonitorOperation?
    @Published private(set) var refreshing = false
    @Published private(set) var refreshFailure: String?
    @Published private(set) var monitorFailure: String?
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
    private var statusRevision = 0

    init(loginItem: LoginItemController = LoginItemController()) {
        self.loginItem = loginItem
        let backend = self.backend
        history = HistoryModel { query in try await backend.history(query) }
        dismissedWatcherErrorAt = UserDefaults.standard.string(forKey: "dismissedWatcherErrorAt") ?? ""
    }

    var dirtyRules: Bool { rules != savedRules || autoActions != savedAutoActions }
    var dirtySettings: Bool { monitor != savedMonitor || actions != savedActions }
    var settingsValidation: String? {
        guard let monitor, let actions else { return nil }
        guard (1...365).contains(monitor.logRetentionDays), (1...100).contains(monitor.logRetentionCount) else {
            return "日志保留天数须为 1–365，保留份数须为 1–100。"
        }
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
    var applicationCandidates: [Candidate] { status?.assessment.candidates.filter { $0.target?.protected == false } ?? [] }
    var systemEnabled: Bool { configuration?.notifications.systemEnabled ?? false }
    var enabledChannels: Int { (systemEnabled ? 1 : 0) + channels.filter { $0.enabled && $0.ready }.count }
    var permissionText: String {
        switch permission { case .authorized, .provisional: "已授权"; case .denied: "权限已关闭"; default: "尚未授权" }
    }
    var monitoringState: MonitoringState { MonitoringState(watcherRunning: status?.watcherRunning, pausedUntil: status?.pausedDate) }
    var recentWatcherError: WatcherHealth? {
        guard let health = status?.watcherHealth, !health.lastError.isEmpty,
              health.lastErrorAt != dismissedWatcherErrorAt else { return nil }
        return health
    }
    func dismissRecentWatcherError() {
        guard let health = recentWatcherError else { return }
        dismissedWatcherErrorAt = health.lastErrorAt
        UserDefaults.standard.set(health.lastErrorAt, forKey: "dismissedWatcherErrorAt")
    }
    var monitoringWarning: String? {
        guard status?.watcherRunning == true else { return nil }
        if let refreshFailure { return "状态读取失败，暂时无法确认监控采样：" + refreshFailure }
        guard let health = status?.watcherHealth else { return "监控未提供采样记录，暂时无法确认监控是否正常。" }
        return health.warning
    }
    var monitoringBadge: String {
        if monitoringWarning != nil { return "采样异常" }
        if status?.watcherRunning == true, status?.watcherHealth?.status == "starting" { return "等待采样" }
        return monitoringState.badge
    }
    var menuSymbol: String {
        if monitoringWarning != nil { return "exclamationmark.circle" }
        return switch monitoringState {
        case .paused: "pause.circle"
        case .running: status?.assessment.eligible == true ? "exclamationmark.circle" : "moon.stars"
        case .stopped, .unavailable: "moon.zzz"
        }
    }
    var headline: String {
        if let monitorOperation { return monitorOperation.title }
        if status == nil, refreshFailure != nil { return "暂时无法读取状态" }
        if refreshFailure != nil { return "当前状态暂不可确认" }
        if monitoringState == .running { return status?.watcherHealth?.title ?? "监控采样状态未知" }
        return monitoringState.title
    }
    var monitoringDetail: String {
        if monitorOperation != nil { return "正在确认监控运行状态…" }
        if let monitorFailure { return monitorFailure }
        guard let status else { return "正在读取…" }
        if let warning = monitoringWarning {
            return monitoringState == .paused ? "提醒与处理已暂停。" + warning : warning
        }
        switch monitoringState {
        case .paused:
            return "暂停至 \(ClockText.time(status.pausedUntil))。" + (status.watcherRunning ? "继续采样，可提前恢复。" : "监控未运行，可恢复并启动。")
        case .stopped:
            if let health = recentWatcherError { return "最近监控错误：" + health.lastError }
            return "启动后持续检查，关闭窗口后仍会监控。"
        case .running:
            if status.watcherHealth?.status == "starting" { return "进程已启动，正在等待首次采样完成。" }
            return (status.assessment.eligible && !applicationCandidates.isEmpty ? "\(applicationCandidates.count) 个应用需要关注。" : "") + status.assessment.reason
        case .unavailable: return "正在读取…"
        }
    }
    func start(launchedAtLogin: Bool = false) async {
        guard !started else { return }; started = true
        busy = true
        defer { busy = false }
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
        let recoveringUpdate = await recoverAfterUpdate()
        loginItem.refresh()
        if launchedAtLogin && loginItem.enabled && !recoveringUpdate {
            do {
                let current = try await backend.status()
                if !current.watcherRunning { try await launchMonitor() }
                await refresh()
            } catch { monitorFailure = error.localizedDescription; self.error = "登录后启动监控失败：\(error.localizedDescription)" }
        }
        startRefreshTimer()
        updater.start(model: self)
    }
    private func startRefreshTimer() {
        timerTask?.cancel()
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
        guard !refreshing, monitorOperation == nil, !quitting else { return }; refreshing = true; defer { refreshing = false }
        let revision = statusRevision
        do {
            let latest = try await backend.status()
            let envelope = try await backend.configuration()
            let logFailure = await backend.logFailure()
            guard monitorOperation == nil, !quitting, revision == statusRevision else { return }
            self.logFailure = logFailure
            status = latest
            load(envelope.config, resetRules: !dirtyRules, resetSettings: !dirtySettings)
            refreshFailure = nil
            if tab == .history { await reloadHistory() }
            if userInitiated { information = "状态已更新。" }
        } catch {
            if revision == statusRevision, monitorOperation == nil, !quitting { refreshFailure = error.localizedDescription }
        }
        // Permission lookup must not hold the status refresh gate while waiting for macOS.
        if permissionTask == nil {
            permissionTask = Task { [weak self] in
                let authorization = await Self.notificationAuthorization()
                self?.permission = authorization
                self?.permissionTask = nil
            }
        }
    }
    private nonisolated static func notificationAuthorization() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // Older SDKs expose UNNotificationSettings as a non-Sendable object.
            // Extract the scalar status in its callback before crossing actors.
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
    func reloadHistory() async {
        guard !quitting else { return }
        await history.refreshIfAtLatest()
    }
    func prepareCatalog() async {
        guard !catalogLoading else { return }; catalogLoading = true; defer { catalogLoading = false }
        do { catalog = await AppCatalog.collect(processes: try await backend.processes()) }
        catch { catalog = await AppCatalog.collect(processes: []); self.error = error.localizedDescription }
    }
    // Each save changes only its own page; draft rules/settings cannot be saved by a channel toggle.
    private func update(resetRules: Bool = false, resetSettings: Bool = false, _ mutation: (inout GuardConfig) throws -> Void) async throws {
        statusRevision += 1
        defer { statusRevision += 1 }
        var envelope = try await backend.configuration()
        configuration = envelope.config
        try mutation(&envelope.config)
        let saved = try await backend.save(envelope)
        load(saved.config, resetRules: resetRules, resetSettings: resetSettings)
        information = status?.watcherRunning == true ? "已保存；监控将在下一次采样时应用。" : "已保存，启动监控后生效。"
    }
    func saveRules() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let rules = self.rules, enabled = autoActions, baseline = savedRules, baselineEnabled = savedAutoActions
        do { try await update(resetRules: true) { try ConfigEdits.rules(rules, enabled: enabled, baseline: baseline, baselineEnabled: baselineEnabled, into: &$0) }; await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func discardRules() {
        if let configuration { load(configuration, resetRules: true) }
        else { rules = savedRules; autoActions = savedAutoActions }
    }
    func discardSettings() {
        if let configuration { load(configuration, resetSettings: true) }
        else { monitor = savedMonitor; actions = savedActions }
    }
    func saveSettings() async {
        guard !busy, let monitor, let actions, let savedMonitor, let savedActions else { return }; busy = true; defer { busy = false }
        if let message = settingsValidation { error = message; return }
        do { try await update(resetSettings: true) { try ConfigEdits.settings(monitor, actions: actions, baselineMonitor: savedMonitor, baselineActions: savedActions, into: &$0) }; await refresh() }
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
        guard !busy, monitoringState == .running else { return }; busy = true; statusRevision += 1; defer { busy = false }
        do { try await backend.pause(minutes: minutes); try await updateMonitorStatus(); information = "已暂停 \(minutes) 分钟，仍继续采样。"; await reloadHistory() }
        catch { self.error = error.localizedDescription }
    }
    func resume() async {
        guard !busy, monitoringState == .paused else { return }; busy = true; statusRevision += 1
        let needsStart = status?.watcherRunning != true
        if needsStart { monitorOperation = .starting; monitorFailure = nil }
        defer { busy = false; monitorOperation = nil }
        do {
            if needsStart { try await launchMonitor() }
            try await backend.resume()
            try await updateMonitorStatus()
            information = needsStart ? "监控已启动，提醒与处理已恢复。" : "已恢复提醒与处理。"
            await reloadHistory()
        } catch { if needsStart { monitorFailure = error.localizedDescription }; self.error = error.localizedDescription }
    }
    private func updateMonitorStatus() async throws {
        // Discard a periodic refresh that sampled before this operation completed.
        statusRevision += 1
        status = try await backend.status()
        refreshFailure = nil
    }
    private func launchMonitor() async throws {
        // Create a default config only when absent; leave unsaved drafts alone.
        let envelope = try await backend.configuration()
        if envelope.revision.isEmpty { _ = try await backend.save(envelope) }
        try await backend.startMonitor()
        try await confirmMonitor(running: true)
    }
    func startMonitor() async {
        guard !busy else { return }; busy = true; monitorOperation = .starting
        information = nil; monitorFailure = nil; statusRevision += 1
        defer { busy = false; monitorOperation = nil }
        do {
            try await launchMonitor()
            information = "监控已启动，关闭窗口后仍会监控。"
        } catch { monitorFailure = error.localizedDescription; self.error = error.localizedDescription }
    }
    func stopMonitor() async {
        guard !busy else { return }; busy = true; monitorOperation = .stopping
        information = nil; monitorFailure = nil; statusRevision += 1
        defer { busy = false; monitorOperation = nil }
        do { try await backend.stopMonitor(); try await confirmMonitor(running: false); information = "监控已停止。" }
        catch { self.error = error.localizedDescription }
    }
    func stopForQuit() async throws {
        screenController.restore()
        guard !busy else { throw BackendFailure(message: "正在完成其他操作，请稍后退出。") }
        busy = true; quitting = true; monitorOperation = .stopping; information = nil; statusRevision += 1
        defer { busy = false; quitting = false; monitorOperation = nil }
        try await backend.stopMonitor()
        // AppMonitor.stop verifies its owned child has exited. A fresh power
        // snapshot can fail independently and must not prevent quitting.
        timerTask?.cancel()
    }
    func prepareForUpdate(continuingUpdate: Bool = false) async throws {
        guard !screenController.active else { throw BackendFailure(message: "请先结束黑屏，再更新 SleepGuard。") }
        guard !dirtyRules && !dirtySettings else { throw BackendFailure(message: "请先保存或撤销未保存的设置。") }
        guard !busy else { throw BackendFailure(message: "正在完成其他操作，请稍后更新。") }
        busy = true; quitting = true; monitorOperation = .stopping; statusRevision += 1
        let shouldResumeMonitoring: Bool
        do { shouldResumeMonitoring = try await backend.monitoringRequestedForUpdate() }
        catch { busy = false; quitting = false; monitorOperation = nil; throw error }
        do {
            // A failed child can be between retries while watcherRunning is false.
            // Always stop the owner so no retry can launch during installation.
            try await backend.stopMonitor()
            try await confirmMonitor(running: false)
            let recovery = UpdateRecovery(previousBuild: updater.build, watcherWasRunning: shouldResumeMonitoring,
                                          createdAt: Date(), continuingUpdate: continuingUpdate ? true : nil)
            try recovery.save()
            timerTask?.cancel()
        } catch {
            UpdateRecovery.clear()
            if shouldResumeMonitoring { try? await launchMonitor() }
            busy = false; quitting = false; monitorOperation = nil
            startRefreshTimer()
            throw error
        }
    }
    func restoreAfterFailedUpdate() async {
        defer { busy = false; quitting = false; monitorOperation = nil; startRefreshTimer() }
        guard let recovery = try? UpdateRecovery.take() else { return }
        if recovery.watcherWasRunning {
            do { try await launchMonitor() }
            catch { self.error = "更新未完成，监控恢复失败：\(error.localizedDescription)" }
        }
    }
    private func recoverAfterUpdate() async -> Bool {
        var recovering = false
        do {
            guard let recovery = try UpdateRecovery.take() else { return false }
            guard Date().timeIntervalSince(recovery.createdAt) < 1800 else { return false }
            recovering = true
            if recovery.watcherWasRunning && status?.watcherRunning != true {
                try await launchMonitor()
            }
            if recovery.continuingUpdate == true {
                information = "已重新启动，将继续更新。"
            } else if recovery.previousBuild != updater.build {
                information = "已更新到 \(updater.version)，监控已按原状态恢复。"
            } else {
                self.error = "更新未完成，已恢复原有监控状态。"
            }
            await refresh()
        } catch {
            self.error = "更新后监控恢复失败：\(error.localizedDescription)。请在设置中检查监控。"
        }
        return recovering
    }
    private func confirmMonitor(running: Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            let latest = try await backend.status()
            status = latest
            if latest.watcherRunning == running { return }
            try await Task.sleep(for: .milliseconds(300))
        } while Date() < deadline
        throw BackendFailure(message: running ? await backend.startupFailure() : "仍检测到监控进程，请刷新状态或查看运行日志。")
    }
}

enum MonitorOperation {
    case starting, stopping
    var title: String { self == .starting ? "正在启动监控…" : "正在停止监控…" }
}
