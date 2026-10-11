import Foundation

struct GuardConfig: Codable, Equatable, Sendable {
    var monitor: MonitorConfig
    var telegram: LegacyTelegram
    var actions: ActionConfig
    var rules: [AppRule]
    var notifications: NotificationConfig
    var channels: [NotificationChannel]
}
struct MonitorConfig: Codable, Equatable, Sendable {
    var interval: String
    var grace: String
    var wakeGrace: String
    var consecutiveSamples: Int
    var reminderInterval: String
    var notifyCount: Int
    var finalGrace: String
    var retentionDays: Int
    var logRetentionDays: Int = 7
    var logRetentionCount: Int = 10
}
struct LegacyTelegram: Codable, Equatable, Sendable {
    var enabled: Bool
    var chatId: Int64
    var tokenEnv: String
    var keychainService: String
    var timeout: String
}
struct ActionConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var killAfter: String
    var allowSigkill: Bool
    var wait: String
}
struct NotificationConfig: Codable, Equatable, Sendable {
    var systemEnabled: Bool
    var helperPath: String
}
struct AppRule: Codable, Equatable, Identifiable, Sendable {
    var bundleId: String = ""
    var path: String = ""
    var name: String = ""
    var notify: Bool = true
    var process: Bool = false
    var id: String { bundleId.isEmpty ? path : bundleId }
    var label: String {
        if !name.isEmpty { return name }
        return bundleId.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : bundleId
    }
    var actionLabel: String {
        notify ? (process ? "通知并处理" : "仅通知") : (process ? "仅处理" : "忽略")
    }
}
struct NotificationChannel: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString.lowercased()
    var name = ""
    var type = "telegram"
    var enabled = false
    var chatId: Int64 = 0
    var tokenEnv = ""
    var keychainService = ""
    var timeout = "15s"
    var ready: Bool { type == "telegram" }
    var providerName: String { Provider.all.first(where: { $0.id == type })?.name ?? type }
    var icon: String { Provider.all.first(where: { $0.id == type })?.icon ?? "bell" }
}
struct Provider: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let ready: Bool
    static let all = [
        Provider(id: "telegram", name: "Telegram · 电报", icon: "paperplane", ready: true),
        Provider(id: "webhook", name: "Webhook", icon: "link", ready: false),
        Provider(id: "feishu", name: "飞书", icon: "bubble.left.and.bubble.right", ready: false),
        Provider(id: "slack", name: "Slack", icon: "number", ready: false),
        Provider(id: "email", name: "邮件", icon: "envelope", ready: false)
    ]
}
struct ConfigEnvelope: Codable, Sendable { var config: GuardConfig; var revision: String }
struct GuardProcess: Codable, Identifiable, Sendable {
    var pid: Int32
    var startedMs: Int64
    var uid: Int32
    var name: String
    var path: String
    var bundleId: String?
    var protected: Bool
    var id: Int32 { pid }
}
struct PowerAssertion: Codable, Identifiable, Sendable {
    var id: String
    var type: String
    var name: String
    var holder: GuardProcess
    var target: GuardProcess?
    var attribution: String
}
struct Snapshot: Codable, Sendable {
    var at: String
    var bootId: String
    var wakeAt: String
    var idleSeconds: Double
    var displayAsleep: Bool
    var powerSource: String
    var sleepMinutes: Int
    var displayMinutes: Int
    var sleepDisabled: Bool
    var assertions: [PowerAssertion]
    var diagnostics: [String]?
    var kernelAssertions: String?
}
struct Candidate: Codable, Identifiable, Sendable {
    var key: String
    var label: String
    var target: GuardProcess?
    var assertions: [PowerAssertion]
    var policy: String
    var id: String { key }
    var actionLabel: String { ["notify":"仅通知", "ignore":"忽略", "process":"仅处理", "terminate":"通知并处理"][policy] ?? policy }
}
struct Assessment: Codable, Sendable {
    var eligible: Bool
    var reason: String
    var thresholdSeconds: Double
    var candidates: [Candidate]
}
struct Incident: Codable, Identifiable, Sendable {
    var key: String
    var label: String
    var samples: Int
    var notifications: Int
    var firstSeen: String
    var qualifiedAt: String
    var snoozedUntil: String
    var actionAttempted: Bool
    var actionRetryAt: String?
    var actionResult: String?
    var id: String { key }
}
struct GuardStatus: Codable, Sendable {
    var snapshot: Snapshot
    var assessment: Assessment
    var incidents: [Incident]
    var pausedUntil: String
    var watcherRunning: Bool
    var watcherHealth: WatcherHealth?
    var configPath: String
    var stateDir: String
    var pausedDate: Date? { ClockText.date(pausedUntil) }
    var paused: Bool { (pausedDate ?? .distantPast) > Date() }
}
struct Delivery: Codable, Sendable {
    var channelId: String
    var channelName: String
    var provider: String
    var roundId: String
    var success: Bool
    var message: String
}
struct HistoryEvent: Codable, Identifiable, Sendable {
    var id: Int64
    var at: String
    var incident: String
    var label: String?
    var kind: String
    var message: String
    var delivery: Delivery?
    var displayMessage: String {
        if kind == "paused", let timestamp = message.split(separator: " ").last, let date = ClockText.date(String(timestamp)) {
            let formatter = DateFormatter(); formatter.dateFormat = "M月d日 HH:mm"
            return "暂停至 " + formatter.string(from: date)
        }
        return message
    }
    var title: String { ["detected":"发现持续阻塞", "reset":"条件已解除", "action_attempt":"准备处理", "action_result":"处理结果", "resumed":"监控已恢复", "paused":"提醒与处理已暂停", "notification_sent":"通知已发送", "notification_failed":"通知发送失败", "manual_quit":"请求结束应用", "manual_quit_result":"应用退出结果", "manual_force":"强制结束应用", "manual_force_result":"强制结束结果", "blackout_started":"所有屏幕已黑屏", "blackout_ended":"屏幕已恢复"][kind] ?? kind }
}
struct HistoryGroup: Identifiable {
    var events: [HistoryEvent]
    var id: Int64 { events[0].id }
    var title: String {
        guard events[0].delivery != nil else { return events[0].title }
        let successes = events.filter { $0.delivery?.success == true }.count
        return successes == events.count ? "通知已发送" : successes == 0 ? "通知发送失败" : "通知 · 部分渠道失败"
    }
}
struct CatalogApp: Identifiable, Sendable {
    var id: String
    var name: String
    var bundleId: String
    var path: String
    var appPath: String
    var pid: Int32?
    var group: String
    var protected: Bool
    var rule: AppRule { AppRule(bundleId: bundleId, path: bundleId.isEmpty ? path : "", name: name) }
    var detail: String { protected ? "受保护" : pid.map { "PID \($0)" } ?? "已安装" }
}
enum ManagementTab: String, CaseIterable, Identifiable {
    case status = "状态", rules = "规则", notifications = "通知", history = "历史", settings = "设置", updates = "版本"
    var id: String { rawValue }
    var icon: String { switch self { case .status: "waveform.path.ecg"; case .rules: "slider.horizontal.3"; case .notifications: "bell"; case .history: "clock.arrow.circlepath"; case .settings: "gearshape"; case .updates: "arrow.triangle.2.circlepath" } }
}
enum ClockText {
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func time(_ value: String) -> String { date(value)?.formatted(date: .omitted, time: .shortened) ?? "—" }
    static func preciseTime(_ value: String) -> String { date(value)?.formatted(.dateTime.hour().minute().second()) ?? "—" }
    static func historyTime(_ value: String) -> String {
        guard let date = date(value) else { return "—" }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd\nHH:mm"
        return formatter.string(from: date)
    }
    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(max(0, Int(seconds))) 秒" }
        if seconds >= 3600 {
            let minutes = Int(seconds / 60) % 60
            return "\(Int(seconds / 3600)) 小时" + (minutes > 0 ? " \(minutes) 分钟" : "")
        }
        return "\(Int(seconds / 60)) 分钟"
    }
    static func duration(_ raw: String) -> String { DurationValue.seconds(raw).map { duration($0) } ?? "—" }
    static func seconds(_ raw: String) -> Double { DurationValue.seconds(raw) ?? 0 }
}

struct ManualRequest: Encodable, Sendable {
    let key: String
    let target: GuardProcess
    let force: Bool
}
struct ManualResult: Decodable, Sendable {
    let exited: Bool
    let message: String
}
