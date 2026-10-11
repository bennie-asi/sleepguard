import Foundation

enum MonitoringState: Equatable {
    case unavailable, stopped, running, paused

    init(watcherRunning: Bool?, pausedUntil: Date?, now: Date = Date()) {
        guard let watcherRunning else { self = .unavailable; return }
        if let pausedUntil, pausedUntil > now { self = .paused }
        else { self = watcherRunning ? .running : .stopped }
    }

    var title: String {
        switch self {
        case .unavailable: "正在读取状态…"
        case .stopped: "监控未运行"
        case .running: "监控运行中"
        case .paused: "提醒与处理已暂停"
        }
    }
    var badge: String {
        switch self {
        case .unavailable: "读取中"
        case .stopped: "未运行"
        case .running: "运行中"
        case .paused: "已暂停"
        }
    }
    var symbol: String {
        switch self {
        case .unavailable, .stopped: "power"
        case .running: "checkmark.circle"
        case .paused: "pause.circle.fill"
        }
    }
}
