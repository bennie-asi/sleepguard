import AppKit
import Foundation
import Sparkle

@MainActor final class UpdateController: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = UpdateController()

    @Published private(set) var status = "准备检查更新"
    @Published private(set) var availableVersion: String?
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    @Published private(set) var working = false
    @Published private(set) var installPrepared = false
    @Published private(set) var cancellingScheduledInstallation = false

    weak var model: GuardModel?
    private var started = false
    private var installingByRequest = false
    private var cancellationRequested = false
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private var cancelCheck: (() -> Void)?
    private var cancelDownload: (() -> Void)?
    private var scheduledInstallationQueued = false
    private var cancellationTask: Task<Void, Never>?
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }
    var lastCheck: Date? { started ? updater.lastUpdateCheckDate : nil }
    var ready: Bool { started }
    var canCancel: Bool { cancelCheck != nil || cancelDownload != nil }
    var canQuitWithoutUnexpectedInstall: Bool { !cancellingScheduledInstallation }
    var automaticChecks: Bool { started ? updater.automaticallyChecksForUpdates : (UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true) }
    var automaticInstalls: Bool { started ? updater.automaticallyDownloadsUpdates : (UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? false) }

    func start(model: GuardModel) {
        self.model = model
        guard !started else { return }
        do {
            try updater.start()
            started = true
            status = "已准备检查更新"
            if CommandLine.arguments.contains(UpdateRelaunch.resumeArgument) {
                Task { [weak self] in
                    guard let self else { return }
                    for _ in 0..<50 {
                        if self.updater.canCheckForUpdates { self.installNow(); return }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    self.error = "更新器暂时不可用，请重试更新。"
                }
            }
        } catch {
            self.error = error.localizedDescription
            status = "更新服务无法启动"
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard started else { return }
        updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updater.automaticallyDownloadsUpdates = false
            cancelScheduledInstallationIfNeeded()
        }
        objectWillChange.send()
    }

    func setAutomaticInstalls(_ enabled: Bool) {
        guard started, updater.automaticallyChecksForUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
        if enabled { cancellingScheduledInstallation = false }
        else { cancelScheduledInstallationIfNeeded() }
        objectWillChange.send()
    }

    private func cancelScheduledInstallationIfNeeded() {
        guard scheduledInstallationQueued else { return }
        cancellingScheduledInstallation = true
        status = "正在取消退出时安装…"
        guard cancellationTask == nil else { return }
        cancellationTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<25 {
                if !self.cancellingScheduledInstallation { break }
                if self.updater.canCheckForUpdates && !self.updater.sessionInProgress {
                    self.working = true
                    self.updater.checkForUpdates()
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if self.cancellingScheduledInstallation && !self.working {
                self.error = "暂时无法取消已排队的安装，请稍后重试。"
            }
            self.cancellationTask = nil
        }
    }

    func retryScheduledInstallationCancellation() {
        guard cancellingScheduledInstallation else { return }
        error = nil
        cancelScheduledInstallationIfNeeded()
    }

    func check() {
        guard started, !working, !cancellingScheduledInstallation, updater.canCheckForUpdates else { return }
        error = nil
        cancellationRequested = false
        working = true
        status = "正在检查更新…"
        updater.checkForUpdateInformation()
    }

    func installNow() {
        guard started, !working, !cancellingScheduledInstallation else { return }
        if let model {
            if model.screenController.active { error = "请先结束黑屏，再更新 SleepGuard。"; return }
            if model.dirtyRules || model.dirtySettings { error = "请先保存或撤销未保存的设置。"; return }
            if model.busy { error = "正在完成其他操作，请稍后更新。"; return }
        }
        guard updater.canCheckForUpdates else { return }
        error = nil
        cancellationRequested = false
        installingByRequest = true
        working = true
        if !UpdateRelaunch.executableIsCurrent {
            status = "正在重新启动并继续更新…"
            Task { [weak self] in
                guard let self, let model = self.model else { return }
                do {
                    try await model.prepareForUpdate(continuingUpdate: true)
                    self.installPrepared = true
                    try await UpdateRelaunch.prepareHelper()
                    NSApp.terminate(nil)
                } catch {
                    self.installPrepared = false
                    await model.restoreAfterFailedUpdate()
                    self.error = error.localizedDescription
                    self.status = "更新器重新启动失败"
                    self.working = false
                    self.installingByRequest = false
                }
            }
            return
        }
        status = "正在检查更新…"
        updater.checkForUpdates()
    }

    func cancel() {
        if let cancelDownload { cancellationRequested = true; cancelDownload() }
        else if let cancelCheck { cancellationRequested = true; cancelCheck() }
        else { return }
        cancelDownload = nil
        cancelCheck = nil
        installingByRequest = false
        working = false
        progress = nil
        status = "已取消更新"
    }

    // MARK: Sparkle user driver

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks,
                                   automaticUpdateDownloading: NSNumber(value: automaticInstalls),
                                   sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        cancelCheck = cancellation
        status = "正在检查更新…"
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        cancelCheck = nil
        availableVersion = item.displayVersionString
        if cancellingScheduledInstallation {
            if state.stage == .installing {
                cancellingScheduledInstallation = false
                scheduledInstallationQueued = false
                working = false
                status = "已取消退出时安装；仍可手动更新"
                return .skip
            }
            if state.stage == .downloaded {
                cancellingScheduledInstallation = false
                scheduledInstallationQueued = false
                working = false
                status = "已关闭自动安装；仍可手动更新"
                return .dismiss
            }
        }
        status = "发现新版本 \(item.displayVersionString)"
        if item.isInformationOnlyUpdate || item.isMajorUpgrade {
            installingByRequest = false
            working = false
            return .dismiss
        }
        if installingByRequest {
            if state.stage == .installing {
                do {
                    try await prepareInstallation()
                    return .install
                } catch {
                    self.error = error.localizedDescription
                    status = "更新已暂缓"
                    working = false
                    installingByRequest = false
                    return .skip
                }
            }
            status = "正在下载 \(item.displayVersionString)…"
            return .install
        }
        working = false
        return .dismiss
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error) async {
        cancelCheck = nil
        installingByRequest = false
        working = false
        availableVersion = nil
        status = cancellationRequested ? "已取消更新" : (cancellingScheduledInstallation ? "取消已排队的安装失败" : "未发现可安装的新版本")
    }

    func showUpdaterError(_ error: any Error) async {
        self.error = cancellationRequested ? nil : UpdateFailure.details(for: error)
        status = cancellationRequested ? "已取消更新" : UpdateFailure.title(for: error)
        working = false
        installingByRequest = false
        progress = nil
        cancelCheck = nil
        cancelDownload = nil
        if cancellingScheduledInstallation { status = "取消已排队的安装失败" }
        if installPrepared {
            installPrepared = false
            await model?.restoreAfterFailedUpdate()
        }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        expectedBytes = 0
        receivedBytes = 0
        progress = nil
        working = true
        status = "正在下载更新…"
    }

    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {
        expectedBytes = length
        progress = length > 0 ? 0 : nil
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        if expectedBytes > 0 { progress = min(1, Double(receivedBytes) / Double(expectedBytes)) }
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        progress = nil
        status = "正在验证并解压更新…"
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        self.progress = progress
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        progress = nil
        if cancellingScheduledInstallation {
            cancellingScheduledInstallation = false
            scheduledInstallationQueued = false
            working = false
            status = "已取消退出时安装；仍可手动更新"
            return .skip
        }
        guard installingByRequest else {
            working = false
            status = "更新已下载，退出时安装"
            return .dismiss
        }
        do {
            try await prepareInstallation()
            return .install
        } catch {
            self.error = error.localizedDescription
            status = "更新已暂缓"
            working = false
            installingByRequest = false
            return .skip
        }
    }

    private func prepareInstallation() async throws {
        guard !installPrepared else { return }
        guard let model else { throw BackendFailure(message: "无法确认后台状态，请重试更新。") }
        status = "正在准备安装更新…"
        try await model.prepareForUpdate()
        installPrepared = true
        status = "正在安装并重新打开…"
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        status = "正在安装并重新打开…"
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}

    func dismissUpdateInstallation() {
        cancelCheck = nil
        cancelDownload = nil
        progress = nil
        if !installPrepared { working = false; installingByRequest = false }
    }

    // MARK: Sparkle updater delegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        if let override = ProcessInfo.processInfo.environment["SLEEPGUARD_UPDATE_FEED"],
           URL(string: override)?.scheme == "https" || override.hasPrefix("http://127.0.0.1:") {
            return override
        }
        let name: String
        #if arch(arm64)
        name = "appcast-arm64.xml"
        #else
        name = "appcast-x86_64.xml"
        #endif
        return "https://github.com/bennie-asi/sleepguard/releases/latest/download/\(name)"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        status = "发现新版本 \(item.displayVersionString)"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availableVersion = nil
        status = "未发现可安装的新版本"
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        scheduledInstallationQueued = true
        availableVersion = item.displayVersionString
        status = "更新已下载，退出时安装"
        if !automaticInstalls { cancelScheduledInstallationIfNeeded() }
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard installPrepared else { return }
        installPrepared = false
        Task { await model?.restoreAfterFailedUpdate() }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error, !installPrepared, !cancellationRequested,
           status != "未发现可安装的新版本",
           self.error == nil,
           status != "取消已排队的安装失败",
           status != "已取消退出时安装；仍可手动更新" {
            self.error = error.localizedDescription
            status = "检查更新失败"
        }
        if !installPrepared { working = false; installingByRequest = false }
        cancellationRequested = false
        objectWillChange.send()
    }
}
