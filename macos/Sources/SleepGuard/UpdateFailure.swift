import Foundation
import Sparkle

enum UpdateFailure {
    static func title(for error: any Error) -> String {
        var current: NSError? = error as NSError
        var code: Int?
        for _ in 0..<5 {
            guard let failure = current else { break }
            if failure.domain == SUSparkleErrorDomain { code = failure.code }
            current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        guard let code else { return "更新失败" }
        switch code {
        case 2000..<3000: return "下载更新失败"
        case 3000..<4000, 4009: return "验证更新失败"
        case 4000..<5000: return "安装更新失败"
        default: return "检查更新失败"
        }
    }

    static func details(for error: any Error) -> String {
        var current: NSError? = error as NSError
        var messages: [String] = []
        for _ in 0..<5 {
            guard let failure = current else { break }
            for message in [failure.localizedDescription, failure.localizedFailureReason].compactMap({ $0 }) {
                if !messages.contains(message) { messages.append(message) }
            }
            current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return messages.joined(separator: "\n")
    }
}
