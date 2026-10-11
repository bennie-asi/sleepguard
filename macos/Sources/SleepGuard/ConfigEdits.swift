import Foundation

// Compare the page with its editing baseline before applying a draft to a freshly
// read envelope. The backend revision protects the remaining read/save gap.
enum ConfigEdits {
    static func rules(_ draft: [AppRule], enabled: Bool, baseline: [AppRule], baselineEnabled: Bool,
                      into current: inout GuardConfig) throws {
        guard current.rules == baseline, current.actions.enabled == baselineEnabled else {
            throw BackendFailure(message: "应用规则已被其他操作修改。草稿已保留；请撤销并查看最新规则后重新编辑。")
        }
        current.rules = draft
        current.actions.enabled = enabled
    }

    static func settings(_ monitor: MonitorConfig, actions: ActionConfig,
                         baselineMonitor: MonitorConfig, baselineActions: ActionConfig,
                         into current: inout GuardConfig) throws {
        guard current.monitor == baselineMonitor,
              current.actions.wait == baselineActions.wait,
              current.actions.killAfter == baselineActions.killAfter,
              current.actions.allowSigkill == baselineActions.allowSigkill else {
            throw BackendFailure(message: "监控设置已被其他操作修改。草稿已保留；请撤销并查看最新设置后重新编辑。")
        }
        current.monitor = monitor
        current.actions.wait = actions.wait
        current.actions.killAfter = actions.killAfter
        current.actions.allowSigkill = actions.allowSigkill
    }
}
