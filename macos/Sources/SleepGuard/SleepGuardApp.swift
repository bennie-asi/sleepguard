import AppKit
import SwiftUI
import UserNotifications
import Darwin

@main enum SleepGuardLaunch {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--run-monitor" { exit(MonitorHelper.run()) }
        if CommandLine.arguments.contains("--deliver-notification") { exit(NotificationHelper.deliver()) }
        if CommandLine.arguments.contains("--notification-status") { exit(NotificationHelper.status()) }
        if CommandLine.arguments.contains("--send-keychain-telegram") { exit(TelegramHelper.send()) }
        if CommandLine.arguments.dropFirst().first == "--check-keychain" { exit(NativeChecks.keychain()) }
        if CommandLine.arguments.dropFirst().first == "--check-keychain-item" { exit(NativeChecks.item()) }
        SleepGuardApp.main()
    }
}
struct SleepGuardApp: App {
    @NSApplicationDelegateAdaptor(GuardAppDelegate.self) var delegate
    @StateObject private var model = GuardModel()
    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            MenuIcon(model: model, delegate: delegate)
        }.menuBarExtraStyle(.window)
        Window("SleepGuard", id: "management") {
            ManagementView(model: model).onAppear { delegate.model = model }
        }.defaultSize(width: 640, height: 720).windowResizability(.contentMinSize)
    }
}
struct MenuIcon: View {
    @ObservedObject var model: GuardModel
    let delegate: GuardAppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: model.menuSymbol)
            .accessibilityLabel("SleepGuard")
            .onReceive(NotificationCenter.default.publisher(for: .sleepGuardShowWindow)) { _ in
                NotificationCenter.default.post(name: .sleepGuardDismissMenu, object: nil)
                openWindow(id: "management")
                NSApp.activate(ignoringOtherApps: true)
            }
            .task {
                delegate.model = model
                await model.start()
                if CommandLine.arguments.contains("--show-window") {
                    openWindow(id: "management")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
@MainActor final class GuardAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var model: GuardModel?
    private var terminationPending = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = Bundle.main.url(forResource: "SleepGuard", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) {
            NSApp.applicationIconImage = icon
        }
        UNUserNotificationCenter.current().delegate = self
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .sleepGuardShowWindow, object: nil)
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        let alert = NSAlert()
        alert.messageText = "退出 SleepGuard？"
        alert.informativeText = "将同时停止后台监控。配置和历史会保留。" + ((model?.dirtyRules == true || model?.dirtySettings == true) ? "\n未保存的更改将丢失。" : "")
        alert.addButton(withTitle: "退出并停止后台")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        terminationPending = true
        let guardModel = model ?? GuardModel()
        Task {
            do {
                try await guardModel.stopForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminationPending = false
                sender.reply(toApplicationShouldTerminate: false)
                let failure = NSAlert()
                failure.messageText = "未能退出 SleepGuard"
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: "好")
                failure.runModal()
            }
        }
        return .terminateLater
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // System notifications are an independent channel; opening one does not change rules.
        completionHandler()
    }
}
extension Notification.Name {
    static let sleepGuardShowWindow = Notification.Name("SleepGuardShowWindow")
    static let sleepGuardDismissMenu = Notification.Name("SleepGuardDismissMenu")
}
private final class NotificationResult: @unchecked Sendable {
    let lock = NSLock()
    private var value = false
    func set(_ value: Bool) { lock.withLock { self.value = value } }
    func get() -> Bool { lock.withLock { value } }
}
enum NotificationHelper {
    static func status() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0), result = NotificationResult()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            result.set(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 8) == .success else { return 2 }
        print(result.get() ? "authorized" : "not-authorized")
        return 0
    }
    static func deliver() -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 1024 * 1024, let message = try? JSONDecoder().decode([String:String].self, from: data), let title = message["title"], let body = message["body"] else { return 2 }
        let center = UNUserNotificationCenter.current(), semaphore = DispatchSemaphore(value: 0), result = NotificationResult()
        center.getNotificationSettings { settings in
            result.set(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional); semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 4) == .success, result.get() else { return 3 }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        result.set(false)
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in result.set(error == nil); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 4) == .success else { return 4 }
        return result.get() ? 0 : 4
    }
}
