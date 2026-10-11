import AppKit
import SwiftUI

struct LoginItemSection: View {
    @ObservedObject var controller: LoginItemController
    var disabled = false

    var body: some View {
        SectionBox {
            SwitchRow(title: "登录时自动启动", detail: "登录 macOS 后启动 SleepGuard 并开始监控。更改立即生效。",
                      isOn: Binding(get: { controller.selected }, set: { enabled in
                Task { await controller.setEnabled(enabled) }
            })).disabled(disabled || controller.changing)
            if controller.changing {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在更新登录项…") }
                    .font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 14)
            }
            if controller.requiresApproval {
                Text("等待系统允许。请在“登录项”中允许 SleepGuard，允许前不会自动启动。")
                    .font(.caption).foregroundStyle(.orange).padding([.horizontal, .bottom], 14)
            }
            if let failure = controller.failure {
                Text(failure).font(.caption).foregroundStyle(.orange).padding([.horizontal, .bottom], 14)
            }
            Divider()
            HStack {
                Text("关闭不停止当前监控；退出应用保留此设置。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("系统登录项") { controller.openSettings() }.font(.caption)
            }.padding(14)
        }
        .onAppear { controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refresh()
        }
    }
}
