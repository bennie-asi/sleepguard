import Foundation

@main struct ConfigEditsChecks {
    static func fixture() -> GuardConfig {
        GuardConfig(monitor: MonitorConfig(interval: "60s", grace: "5m", wakeGrace: "2m", consecutiveSamples: 3, reminderInterval: "10m", notifyCount: 3, finalGrace: "10m", retentionDays: 30),
                    telegram: LegacyTelegram(enabled: false, chatId: 0, tokenEnv: "", keychainService: "", timeout: "15s"),
                    actions: ActionConfig(enabled: false, killAfter: "15s", allowSigkill: false, wait: "30m"),
                    rules: [AppRule(bundleId: "test.app")], notifications: NotificationConfig(systemEnabled: false, helperPath: ""), channels: [])
    }
    static func main() throws {
        let baseline = fixture()
        var draftRules = baseline.rules
        draftRules[0].process = true
        var current = baseline
        current.rules.append(AppRule(bundleId: "external.app"))
        let externallySaved = current
        do {
            try ConfigEdits.rules(draftRules, enabled: true, baseline: baseline.rules, baselineEnabled: false, into: &current)
            fatalError("stale rules overwrote an external addition")
        } catch { assert(current == externallySaved) }
        current = baseline; current.actions.enabled = true
        do {
            try ConfigEdits.rules(draftRules, enabled: false, baseline: baseline.rules, baselineEnabled: false, into: &current)
            fatalError("stale draft overwrote external action switch")
        } catch { assert(current.actions.enabled) }

        current = baseline
        current.notifications.systemEnabled = true
        current.channels = [NotificationChannel(name: "New channel")]
        current.monitor.interval = "90s"
        try ConfigEdits.rules(draftRules, enabled: true, baseline: baseline.rules, baselineEnabled: false, into: &current)
        assert(current.rules == draftRules && current.actions.enabled)
        assert(current.notifications.systemEnabled && current.channels.count == 1 && current.monitor.interval == "90s")

        var draftMonitor = baseline.monitor; draftMonitor.interval = "120s"
        var draftActions = baseline.actions; draftActions.wait = "1h"
        for field in ["interval", "wait", "killAfter", "allowSigkill"] {
            current = baseline
            switch field {
            case "interval": current.monitor.interval = "90s"
            case "wait": current.actions.wait = "2h"
            case "killAfter": current.actions.killAfter = "30s"
            default: current.actions.allowSigkill = true
            }
            let external = current
            do {
                try ConfigEdits.settings(draftMonitor, actions: draftActions, baselineMonitor: baseline.monitor, baselineActions: baseline.actions, into: &current)
                fatalError("stale settings overwrote \(field)")
            } catch { assert(current == external) }
        }
        current = baseline; current.actions.enabled = true; current.rules.append(AppRule(bundleId: "external.app"))
        try ConfigEdits.settings(draftMonitor, actions: draftActions, baselineMonitor: baseline.monitor, baselineActions: baseline.actions, into: &current)
        assert(current.actions.enabled && current.rules.count == 2 && current.monitor.interval == "120s" && current.actions.wait == "1h")
        let refreshed = current
        try ConfigEdits.rules(refreshed.rules, enabled: false, baseline: refreshed.rules, baselineEnabled: true, into: &current)
        assert(!current.actions.enabled && current.rules.count == 2)

        let stale = WatcherHealth(status: "stale", lastSuccess: "2026-10-11T01:00:00Z", lastError: "", lastErrorAt: "0001-01-01T00:00:00Z")
        assert(stale.warning != nil && stale.title != "监控运行中" && stale.hasSuccess)
        let starting = WatcherHealth(status: "starting", lastSuccess: "0001-01-01T00:00:00Z", lastError: "", lastErrorAt: "0001-01-01T00:00:00Z")
        assert(!starting.hasSuccess && starting.title == "等待监控首次采样")
        print("Config edit checks passed: stale drafts rejected, unrelated changes retained, refreshed edits accepted; health labels verified.")
    }
}
