import Foundation

struct WatcherHealth: Codable, Sendable {
    var status: String
    var lastSuccess: String
    var lastError: String
    var lastErrorAt: String

    var warning: String? {
        switch status {
        case "stale": "监控采样超时，进程仍在但未按时完成采样。"
        case "failed": "监控采样失败：" + lastError
        case "unknown": "监控未提供采样记录，暂时无法确认监控是否正常。"
        default: nil
        }
    }
    var hasSuccess: Bool { !lastSuccess.hasPrefix("0001-") && !lastSuccess.isEmpty }
    var title: String {
        switch status {
        case "starting": "等待监控首次采样"
        case "stale": "监控采样超时"
        case "failed": "监控采样失败"
        case "unknown": "监控采样状态未知"
        default: "监控运行中"
        }
    }
}
