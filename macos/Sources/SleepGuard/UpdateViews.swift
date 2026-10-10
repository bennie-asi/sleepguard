import SwiftUI

struct UpdatePage: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        PageHeading(title: "版本与更新", detail: "直接在 SleepGuard 中安装新版本。") { EmptyView() }
        Text("当前版本").font(.caption).foregroundStyle(.secondary)
        SectionBox {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SleepGuard \(updater.version)").font(.title3.weight(.medium))
                    Text("构建 \(updater.build) · \(updater.architecture)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新") { updater.check() }
                    .disabled(!updater.ready || updater.working || updater.cancellingScheduledInstallation)
            }.padding(14)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(updater.status).font(.headline)
                    Spacer()
                    if updater.working { ProgressView().controlSize(.small) }
                }
                if let version = updater.availableVersion {
                    Text("可用版本 \(version) · GitHub Releases").font(.caption).foregroundStyle(.secondary)
                }
                if let progress = updater.progress {
                    ProgressView(value: progress).accessibilityLabel("更新进度")
                }
                if let error = updater.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if updater.cancellingScheduledInstallation {
                    Button("重试取消退出时安装") { updater.retryScheduledInstallationCancellation() }
                        .disabled(updater.working)
                }
                HStack(spacing: 10) {
                    Button("立即更新") { updater.installNow() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updater.ready || updater.working || updater.cancellingScheduledInstallation)
                    if updater.working && updater.canCancel { Button("取消更新") { updater.cancel() } }
                }
                Text("点击后自动下载、校验、安装并重新打开；后台按更新前的状态恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                if let lastCheck = updater.lastCheck {
                    Text("上次检查：\(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        Text("更新偏好").font(.caption).foregroundStyle(.secondary)
        SectionBox {
            SwitchRow(title: "自动检查新版本", detail: "运行期间每天检查；关闭后仍可手动检查。",
                      isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
            Divider()
            SwitchRow(title: "自动下载并安装", detail: "后台下载完成后，在退出 SleepGuard 时安装。",
                      isOn: Binding(get: { updater.automaticInstalls }, set: { updater.setAutomaticInstalls($0) }))
                .disabled(!updater.automaticChecks)
        }
        Text("更新来源").font(.caption).foregroundStyle(.secondary)
        SectionBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Releases")
                    Text("bennie-asi / sleepguard · 正式版").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(14)
        }
    }
}
