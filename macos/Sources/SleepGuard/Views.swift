import AppKit
import SwiftUI

struct AppIcon: View {
    var path: String
    private var iconPath: String {
        guard let range = path.range(of: ".app/") else { return path }
        return String(path[..<range.lowerBound]) + ".app"
    }
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath)).resizable().frame(width: 30, height: 30)
    }
}
struct QuietNotice: View {
    var text: String
    var warning = false
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warning ? Color.orange : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(11)
            .background(warning ? Color.orange.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}
struct SectionBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }
}
struct SwitchRow: View {
    let title: String
    var detail = ""
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).fixedSize().accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }
}
struct EmptyStateRow: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        SectionBox {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.secondary).frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(20)
        }
    }
}
struct WatchStateBadge: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        HStack(spacing: 6) {
            if model.serviceOperation != nil { ProgressView().controlSize(.small) }
            else { Circle().fill(model.monitoringState.color).frame(width: 6, height: 6) }
            Text(model.serviceOperation?.title ?? model.monitoringState.badge)
                .font(.caption).foregroundStyle(.secondary).fixedSize()
        }
    }
}
private extension MonitoringState {
    var color: Color {
        switch self {
        case .running: .green
        case .paused: .yellow
        case .stopped, .unavailable: .secondary
        }
    }
}
struct MonitoringControl: View {
    @ObservedObject var model: GuardModel
    var expanded = false
    var body: some View {
        Group {
            switch model.monitoringState {
            case .running:
                PauseMenu(model: model, expanded: expanded)
            case .paused:
                Button { Task { await model.resume() } } label: {
                    Label(model.status?.watcherRunning == true ? "立即恢复" : "恢复并启动", systemImage: "play.fill")
                        .frame(maxWidth: expanded ? .infinity : nil).padding(.vertical, expanded ? 8 : 2)
                }.buttonStyle(.borderedProminent)
            case .stopped:
                Button { Task { await model.startService() } } label: {
                    Label("启动后台", systemImage: "play.fill")
                        .frame(maxWidth: expanded ? .infinity : nil).padding(.vertical, expanded ? 8 : 2)
                }.buttonStyle(.borderedProminent)
            case .unavailable:
                EmptyView()
            }
        }.disabled(model.busy)
    }
}
struct PauseMenu: View {
    @ObservedObject var model: GuardModel
    var expanded = false
    @ViewState private var choosing = false
    var body: some View {
        Button { choosing = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill").foregroundStyle(.yellow)
                Text(expanded ? "暂停提醒与处理" : "暂停")
                if expanded { Spacer() }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(HoverButtonStyle()).fixedSize(horizontal: !expanded, vertical: true)
            .accessibilityLabel("暂停提醒与处理").disabled(model.busy)
            .popover(isPresented: $choosing, arrowEdge: .bottom) {
                VStack(spacing: 2) {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        Button {
                            choosing = false
                            Task { await model.pause(minutes: minutes) }
                        } label: {
                            Text(minutes < 60 ? "30 分钟" : "\(minutes / 60) 小时")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                        }.buttonStyle(HoverButtonStyle())
                    }
                }.padding(6).frame(width: 170)
            }
    }
}
struct PageHeading<Actions: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.title2.weight(.semibold)); if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) } }
            Spacer(); actions
        }.padding(.bottom, 3)
    }
}
struct MenuPanel: View {
    @ObservedObject var model: GuardModel
    @Environment(\.openWindow) private var openWindow
    @ViewState private var presentation = MenuPresentation()
    private func show(_ tab: ManagementTab) {
        presentation.dismiss()
        model.tab = tab
        openWindow(id: "management")
        NSApp.activate(ignoringOtherApps: true)
    }
    private var maximumHeight: CGFloat { max(300, min(720, (presentation.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 60) }
    var body: some View {
        ViewThatFits(in: .vertical) {
            panel
            ScrollView(showsIndicators: false) { panel }.frame(height: maximumHeight)
        }.frame(width: 320).frame(maxHeight: maximumHeight)
            .onReceive(NotificationCenter.default.publisher(for: .sleepGuardDismissMenu)) { _ in presentation.dismiss() }
            .background(MenuWindowReader(presentation: presentation).frame(width: 0, height: 0).accessibilityHidden(true))
    }
    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars").font(.title2).foregroundStyle(.blue).frame(width: 34, height: 34).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) { Text("SleepGuard").font(.headline); WatchStateBadge(model: model) }
                Spacer(); Button { show(.settings) } label: { Image(systemName: "gearshape").frame(width: 28, height: 28) }.buttonStyle(HoverButtonStyle()).accessibilityLabel("打开设置")
            }.padding(16)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.headline).font(.system(size: 18, weight: .semibold))
                Text(model.monitoringDetail).font(.system(size: 12)).foregroundStyle(.secondary)
                if let status = model.status {
                    HStack { Text("空闲 \(ClockText.duration(status.snapshot.idleSeconds))"); Spacer(); Text(status.snapshot.powerSource == "AC Power" ? "外接电源" : status.snapshot.powerSource) }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                }
            }.padding(.horizontal, 16).padding(.bottom, 16)
            if !model.applicationCandidates.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.applicationCandidates.prefix(3)) { candidate in
                        Button { show(.status) } label: {
                            HStack { AppIcon(path: candidate.target?.path ?? ""); VStack(alignment: .leading, spacing: 3) { Text(candidate.label).lineLimit(1); Text(candidate.actionLabel).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(HoverButtonStyle()).accessibilityLabel("查看 \(candidate.label) 状态")
                    }
                }.padding(8)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                MonitoringControl(model: model, expanded: true)
                if model.monitoringState == .running { Text("暂停通知与处理，监控继续。").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.padding(16).disabled(model.busy)
            Divider()
            HStack(spacing: 8) {
                ScreenQuickButton(title: "黑屏", detail: "所有屏幕 · 不锁屏", icon: "display") { presentation.dismiss(); Task { await model.blackout() } }
                ScreenQuickButton(title: "锁屏", detail: "立即锁定桌面", icon: "lock") { presentation.dismiss(); model.lockScreen() }
            }.padding(8).disabled(model.busy)
            Divider()
            VStack(spacing: 1) {
                menuButton("查看完整状态", icon: "waveform.path.ecg", tab: .status)
                menuButton("应用规则", icon: "slider.horizontal.3", tab: .rules)
                menuButton("通知渠道", icon: "bell", tab: .notifications)
                menuButton("事件历史", icon: "clock.arrow.circlepath", tab: .history)
            }.padding(6)
            Divider()
            HStack(spacing: 2) {
                Text(model.status.map { "最近检查 \(ClockText.preciseTime($0.snapshot.at))" } ?? "等待采样").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                RefreshButton(isRefreshing: model.refreshing, label: "刷新", unavailable: model.busy) { await model.refresh(userInitiated: true) }.foregroundStyle(Color.accentColor)
                Button { presentation.dismiss(); NSApp.terminate(nil) } label: { Text("退出").font(.system(size: 12)).padding(6) }.buttonStyle(HoverButtonStyle()).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 6)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).padding(12) }
            if let failure = model.refreshFailure { Text(failure).font(.caption).foregroundStyle(.orange).padding(12) }
        }.frame(width: 320)
    }
    private func menuButton(_ label: String, icon: String, tab: ManagementTab) -> some View {
        Button { show(tab) } label: {
            HStack(spacing: 10) {
                Image(systemName: tab == .notifications && model.enabledChannels > 0 ? "bell.badge.fill" : icon)
                    .foregroundStyle(tab == .notifications && model.enabledChannels > 0 ? Color.accentColor : .secondary).frame(width: 18)
                Text(label)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(HoverButtonStyle())
    }
}
struct ManagementView: View {
    @ObservedObject var model: GuardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(ManagementTab.allCases) { tab in
                    Button { model.tab = tab } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab == .notifications && model.enabledChannels > 0 ? "bell.badge.fill" : tab.icon)
                                .foregroundStyle(model.tab == tab || (tab == .notifications && model.enabledChannels > 0) ? Color.accentColor : .secondary)
                            Text(tab.rawValue)
                        }.font(.system(size: 13)).frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
                    }
                        .buttonStyle(HoverButtonStyle(selected: model.tab == tab)).foregroundStyle(model.tab == tab ? Color.accentColor : .primary)
                        .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }.padding(12)
            Divider()
            if let information = model.information {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
                    Text(information).font(.caption)
                    Spacer()
                    Button { model.information = nil } label: { Image(systemName: "xmark").font(.caption) }
                        .buttonStyle(HoverButtonStyle()).foregroundStyle(.secondary).accessibilityLabel("关闭提示")
                }.padding(.horizontal, 20).padding(.vertical, 10).background(Color.accentColor.opacity(0.06))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.tab {
                    case .status: StatusPage(model: model)
                    case .rules: RulesPage(model: model)
                    case .notifications: NotificationsPage(model: model)
                    case .history: HistoryPage(model: model)
                    case .settings: SettingsPage(model: model)
                    }
                }.frame(maxWidth: 760, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }.id(model.tab).transition(.opacity)
            if model.tab == .rules || model.tab == .settings {
                Divider()
                SaveBar(model: model).padding(.horizontal, 20).padding(.vertical, 12)
            }
        }.background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 560, minHeight: 520)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.tab)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.information != nil)
            .task { await model.start() }
            .onChange(of: model.tab) { _ in if model.tab == .history { Task { await model.reloadHistory() } } }
            .alert("SleepGuard", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct SaveBar: View {
    @ObservedObject var model: GuardModel
    private var rules: Bool { model.tab == .rules }
    private var dirty: Bool { rules ? model.dirtyRules : model.dirtySettings }
    private var validation: String? { rules ? nil : model.settingsValidation }
    var body: some View {
        HStack(spacing: 10) {
            Text(validation ?? (dirty ? "有未保存的更改" : "未修改")).font(.caption)
                .foregroundStyle(validation == nil ? Color.secondary : .red)
            Spacer(minLength: 10)
            Button("撤销") { if rules { model.discardRules() } else { model.discardSettings() } }.disabled(!dirty || model.busy)
            Button("保存并应用") { Task { if rules { await model.saveRules() } else { await model.saveSettings() } } }
                .buttonStyle(.borderedProminent).disabled(!dirty || model.busy || validation != nil)
        }
    }
}
struct StatusPage: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        PageHeading(title: "当前状态", detail: model.status.map { "最近检查：\(ClockText.preciseTime($0.snapshot.at))" } ?? "尚未读取状态") {
            HStack(spacing: 8) {
                RefreshButton(isRefreshing: model.refreshing, unavailable: model.busy) { await model.refresh(userInitiated: true) }
            }
        }
        if let failure = model.refreshFailure { QuietNotice(text: failure + (model.status == nil ? "" : " 显示的是上次成功读取的状态。"), warning: true) }
        if let status = model.status {
            StatusSummary(model: model)
            if model.applicationCandidates.isEmpty { EmptyStateRow(icon: "checkmark.shield", title: "暂无阻塞休眠的应用", detail: "系统和外设请求可在下方展开查看。") }
            ForEach(model.applicationCandidates) { candidate in
                SectionBox {
                    HStack { AppIcon(path: candidate.target?.path ?? ""); VStack(alignment: .leading, spacing: 4) { Text(candidate.label).font(.headline); Text(candidate.target.map { "PID \($0.pid) · \($0.bundleId ?? $0.path)" } ?? "责任应用未确定").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(candidate.actionLabel).font(.caption).foregroundStyle(.secondary) }.padding(14)
                    if let incident = status.incidents.first(where: { $0.key == candidate.key }) {
                        Divider()
                        HStack { Text("连续检测 \(incident.samples) 次 · 成功通知 \(incident.notifications) 轮"); Spacer(); if incident.actionAttempted { Text(incident.actionResult ?? "已尝试处理") } }.font(.caption).foregroundStyle(.secondary).padding(14)
                        if candidate.policy == "process" || candidate.policy == "terminate" {
                            Text(processingText(incident)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 14)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) { ForEach(candidate.assertions) { assertion in VStack(alignment: .leading, spacing: 3) { Text(assertion.type).font(.system(size: 11, design: .monospaced)); Text(assertion.name).font(.caption).foregroundStyle(.secondary) } } }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    Divider()
                    HStack {
                        Text("手动操作不受自动结束开关影响。").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("调整规则") { model.tab = .rules }.buttonStyle(HoverButtonStyle()).padding(.vertical, 4)
                    }.padding(.horizontal, 14).padding(.top, 10)
                    HStack(spacing: 12) {
                        Button("结束应用…") { model.confirmManualAction(candidate, force: false) }
                        Button("强制结束…", role: .destructive) { model.confirmManualAction(candidate, force: true) }.tint(.red)
                        Spacer()
                    }.padding(14).disabled(model.busy)
                }
            }
            Text("电源与休眠配置").font(.caption).foregroundStyle(.secondary)
            SectionBox {
                statusRow("当前电源", status.snapshot.powerSource == "AC Power" ? "外接电源" : status.snapshot.powerSource == "Battery Power" ? "电池" : status.snapshot.powerSource)
                Divider(); statusRow("用户空闲", ClockText.duration(status.snapshot.idleSeconds))
                Divider(); statusRow("自动系统休眠 / 熄屏", "\(status.snapshot.sleepMinutes) 分钟 / \(status.snapshot.displayMinutes) 分钟")
                if let config = model.configuration { Divider(); statusRow("额外等待时间", ClockText.duration(config.monitor.grace)) }
                Divider(); statusRow("显示器", status.snapshot.displayAsleep ? "已熄屏" : "亮起")
            }
            ExpandableSection("系统与外设请求 · 仅供诊断") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("以下为系统诊断信息。").font(.caption).foregroundStyle(.secondary)
                    ForEach(status.snapshot.assertions) { assertion in Text("\(assertion.holder.name) · \(assertion.type)\n\(assertion.name)").font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    if let text = status.snapshot.kernelAssertions { Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    ForEach(status.snapshot.diagnostics ?? [], id: \.self) { Text($0).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption)
        } else if model.refreshing { ProgressView("读取状态…").frame(maxWidth: .infinity) }
        else { Text("可点击右上角重试刷新。").font(.caption).foregroundStyle(.secondary) }
    }
    private func statusRow(_ name: String, _ value: String) -> some View { HStack { Text(name); Spacer(); Text(value).foregroundStyle(.secondary) }.padding(14) }
    private func processingText(_ incident: Incident) -> String {
        guard model.configuration?.actions.enabled == true else { return "自动结束总开关关闭，处理暂不执行。" }
        guard let qualified = ClockText.date(incident.qualifiedAt), qualified > Date(timeIntervalSince1970: 0), let config = model.configuration else { return "等待连续异常采样达标。" }
        let remaining = qualified.addingTimeInterval(ClockText.seconds(config.actions.wait) + ClockText.seconds(config.monitor.finalGrace)).timeIntervalSinceNow
        return remaining > 0 ? "约 \(ClockText.duration(remaining)) 后复核并请求退出。" : "等待下一次采样复核。"
    }
}
struct StatusSummary: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        SectionBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: model.monitoringState.symbol).font(.system(size: 22)).foregroundStyle(model.monitoringState.color)
                    Text(model.headline).font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 8)
                    if model.serviceOperation != nil { ProgressView().controlSize(.small) }
                    else { WatchStateBadge(model: model) }
                }
                HStack(spacing: 12) {
                    Text(model.monitoringDetail).font(.caption).foregroundStyle(model.serviceFailure == nil ? Color.secondary : .orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    MonitoringControl(model: model)
                }
            }.padding(16)
        }
    }
}
struct RulesPage: View {
    @ObservedObject var model: GuardModel
    @ViewState private var editor: RuleEditorItem?
    var body: some View {
        PageHeading(title: "应用规则", detail: "选择通知、处理或忽略。") { Button { editor = RuleEditorItem(rule: AppRule(), originalID: nil); Task { await model.prepareCatalog() } } label: { Label("添加", systemImage: "plus") }.accessibilityLabel("添加应用规则") }
            .sheet(item: $editor) { item in RuleEditor(model: model, item: item) }
        SectionBox {
            SwitchRow(title: "允许自动结束应用", detail: "仅对勾选“处理”的应用生效。", isOn: $model.autoActions)
        }
        if model.rules.isEmpty { EmptyStateRow(icon: "slider.horizontal.3", title: "暂无应用规则", detail: "未配置的应用默认仅通知。") }
        else {
            SectionBox {
                ForEach($model.rules) { $rule in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { AppIcon(path: iconPath(rule)); VStack(alignment: .leading, spacing: 3) { Text(rule.label).font(.headline); Text(rule.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }; Spacer(); Button { editor = RuleEditorItem(rule: rule, originalID: rule.id); Task { await model.prepareCatalog() } } label: { Image(systemName: "pencil") }.buttonStyle(.plain).accessibilityLabel("编辑 \(rule.label) 规则") }
                        HStack(spacing: 18) { Toggle("通知", isOn: $rule.notify).accessibilityLabel("\(rule.label) 通知"); Toggle("处理", isOn: $rule.process).disabled(AppCatalog.protectedPath(rule.path, bundleId: rule.bundleId)).accessibilityLabel("\(rule.label) 处理"); Spacer(); Text(rule.actionLabel).font(.caption).foregroundStyle(.secondary) }.toggleStyle(.checkbox)
                        if rule.process && !model.autoActions { Text("自动结束总开关关闭，处理暂不执行。").font(.caption).foregroundStyle(.secondary) }
                    }.padding(14)
                    if rule.id != model.rules.last?.id { Divider() }
                }
            }
        }
        Text("通知与处理可分别勾选，都不勾选即忽略。").font(.caption).foregroundStyle(.secondary)
        if model.rules.contains(where: \.process), let config = model.configuration {
            QuietNotice(text: "连续异常 \(config.monitor.consecutiveSamples) 次 → 等待 \(ClockText.duration(config.actions.wait)) → 退出前等待 \(ClockText.duration(config.monitor.finalGrace)) → 复核并请求退出。", warning: true)
        }
    }
    private func iconPath(_ rule: AppRule) -> String { rule.bundleId.isEmpty ? rule.path : NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleId)?.path ?? rule.path }
}
struct NotificationsPage: View {
    @ObservedObject var model: GuardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var editor: ChannelEditorItem?
    var body: some View {
        PageHeading(title: "通知渠道", detail: "已启用 \(model.enabledChannels) 个渠道") { Button { editor = ChannelEditorItem(channel: NotificationChannel(), isNew: true) } label: { Label("添加", systemImage: "plus") }.accessibilityLabel("添加通知渠道") }
            .sheet(item: $editor) { item in ChannelEditor(model: model, item: item) }
        SectionBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack { channelIcon(model.systemEnabled ? "bell.badge.fill" : "bell", enabled: model.systemEnabled); VStack(alignment: .leading, spacing: 4) { Text("系统通知").font(.headline); Text("macOS 通知中心 · \(model.permissionText)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("系统通知", isOn: Binding(get: { model.systemEnabled }, set: { value in Task { await model.setSystemNotifications(value) } })).labelsHidden().toggleStyle(.switch).fixedSize().accessibilityLabel("系统通知开关").disabled(model.busy) }
                HStack { if model.permission == .denied { Button("打开通知设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) } }; Spacer(); Button("测试通知") { Task { await model.testChannel("system") } }.disabled(!model.systemEnabled) }
                result("system")
            }.padding(14)
        }
        Text("其他通知渠道").font(.caption).foregroundStyle(.secondary)
        if model.channels.isEmpty { EmptyStateRow(icon: "paperplane", title: "暂无其他渠道", detail: "点“添加”配置电报或预留其他渠道。") }
        else {
            SectionBox {
                ForEach(model.channels) { channel in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { channelIcon(channel.icon, enabled: channel.enabled && channel.ready); VStack(alignment: .leading, spacing: 4) { Text(channel.name).font(.headline); Text(channel.ready ? "\(channel.providerName) · Chat ID \(String(channel.chatId))" : "\(channel.providerName) · 预留渠道").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle(channel.name, isOn: Binding(get: { channel.enabled }, set: { value in Task { await model.setChannel(channel, enabled: value) } })).labelsHidden().toggleStyle(.switch).fixedSize().accessibilityLabel("\(channel.name) 开关").disabled(!channel.ready || model.busy) }
                        HStack { if !channel.ready { Text("待接入").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("测试") { Task { await model.testChannel(channel.id) } }.disabled(!channel.ready || !channel.enabled).accessibilityLabel("测试 \(channel.name)"); Button("配置…") { editor = ChannelEditorItem(channel: channel, isNew: false) }.accessibilityLabel("配置 \(channel.name)") }
                        result(channel.id)
                    }.padding(14)
                    if channel.id != model.channels.last?.id { Divider() }
                }
            }
        }
    }
    private func channelIcon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name).font(.system(size: 18)).foregroundStyle(enabled ? Color.accentColor : .secondary)
            .frame(width: 34, height: 34).background(enabled ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: enabled)
    }
    @ViewBuilder private func result(_ id: String) -> some View { if let result = model.channelResults[id] { Text(result.message).font(.caption).foregroundStyle(result.success ? Color.green : Color.red).textSelection(.enabled) } }
}
struct HistoryPage: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        PageHeading(title: "事件历史", detail: "通知与处理记录") { RefreshButton(isRefreshing: model.refreshingHistory, help: "刷新历史", unavailable: model.busy) { await model.reloadHistory() } }
        if model.events.isEmpty { EmptyStateRow(icon: "clock.arrow.circlepath", title: "暂无事件", detail: "通知、暂停和处理记录会显示在这里。") }
        ForEach(model.historyGroups) { group in
            HStack(alignment: .top, spacing: 14) {
                Text(ClockText.historyTime(group.events[0].at)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).font(.headline)
                    if let label = group.events[0].label, !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                    ForEach(group.events) { event in
                        if let delivery = event.delivery { Label("\(delivery.channelName) · \(delivery.message)", systemImage: delivery.success ? "checkmark.circle" : "exclamationmark.circle").font(.caption).foregroundStyle(delivery.success ? Color.green : Color.orange) }
                        else { Text(event.displayMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 5)
            Divider()
        }
        ExpandableSection("日志与数据") {
            SectionBox {
                FileLocationRow(title: "运行日志", path: stateDirectory + "/agent.log", openFile: true)
                Divider()
                FileLocationRow(title: "事件数据库", path: stateDirectory + "/state.db")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var stateDirectory: String { model.status?.stateDir ?? NSHomeDirectory() + "/Library/Application Support/sleepguard" }
}
struct FileLocationRow: View {
    let title: String
    let path: String
    var openFile = false
    private var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: openFile ? "doc.text" : "folder").font(.system(size: 12, weight: .medium))
                Spacer()
                Button(openFile ? "打开日志" : "在 Finder 中显示") {
                    let url = URL(fileURLWithPath: path)
                    if openFile { NSWorkspace.shared.open(url) }
                    else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.controlSize(.small).disabled(!exists)
            }
            Text(path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if !exists { Text(openFile ? "后台运行后生成日志。" : "文件尚未生成。").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }
}
struct ServiceControlRow: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("后台服务").font(.system(size: 13, weight: .medium))
                WatchStateBadge(model: model)
                if model.status?.watcherRunning == true { Text("关闭窗口后继续监控，登录后自动启动。").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button(model.status?.watcherRunning == true ? "停止后台" : "启动后台") {
                Task { if model.status?.watcherRunning == true { await model.stopService() } else { await model.startService() } }
            }.disabled(model.busy)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }
}
struct SettingsPage: View {
    @ObservedObject var model: GuardModel
    var body: some View {
        PageHeading(title: "监控设置", detail: "设置检测节奏和等待时间。") { EmptyView() }
        SectionBox { ServiceControlRow(model: model) }
        Text("屏幕操作").font(.caption).foregroundStyle(.secondary)
        ScreenOperationsSection(model: model)
        Text("全局快捷键").font(.caption).foregroundStyle(.secondary)
        ShortcutsSection(controller: model.shortcuts)
        SectionBox {
            if model.monitor != nil {
                DurationInput("检查间隔", value: monitorBinding(\.interval), help: "后台检查状态的间隔", minimum: 1)
                Divider(); DurationInput("额外等待时间", value: monitorBinding(\.grace), help: "超过系统休眠时间后，继续等待多久再判断异常")
                Divider(); DurationInput("唤醒宽限期", value: monitorBinding(\.wakeGrace), help: "电脑唤醒后暂缓异常判断的时间")
            }
        }
        if model.monitor != nil, model.actions != nil {
            ExpandableSection("通知与处理", initiallyExpanded: true) {
                SectionBox {
                    HStack { Text("连续异常采样"); Spacer(); Stepper("\(model.monitor?.consecutiveSamples ?? 3) 次", value: Binding(get: { model.monitor?.consecutiveSamples ?? 3 }, set: { model.monitor?.consecutiveSamples = $0 }), in: 2...20).frame(width: 130) }.padding(14)
                    Divider(); DurationInput("通知间隔", value: monitorBinding(\.reminderInterval))
                    Divider(); DurationInput("处理等待", value: actionBinding(\.wait), help: "连续异常达标后，等待多久开始退出流程")
                    Divider(); DurationInput("退出前等待", value: monitorBinding(\.finalGrace), help: "请求退出前的最后等待，结束后会再次复核")
                    Divider(); DurationInput("请求退出后等待", value: actionBinding(\.killAfter), help: "请求正常退出后，等待应用自行关闭的时间")
                    Divider(); SwitchRow(title: "允许强制结束", detail: "正常退出无响应时使用。", isOn: Binding(get: { model.actions?.allowSigkill ?? false }, set: { model.actions?.allowSigkill = $0 }))
                    Divider(); HStack { Text("历史保留天数"); Spacer(); Stepper("\(model.monitor?.retentionDays ?? 30) 天", value: Binding(get: { model.monitor?.retentionDays ?? 30 }, set: { model.monitor?.retentionDays = $0 }), in: 1...365).frame(width: 130) }.padding(14)
                }.padding(.top, 8)
            }
        }
        if let path = model.status?.configPath {
            ExpandableSection("配置文件") { SectionBox { FileLocationRow(title: "配置文件", path: path) }.padding(.top, 8) }.font(.caption)
        }
    }
    private func monitorBinding(_ key: WritableKeyPath<MonitorConfig, String>) -> Binding<String> { Binding(get: { model.monitor?[keyPath: key] ?? "" }, set: { model.monitor?[keyPath: key] = $0 }) }
    private func actionBinding(_ key: WritableKeyPath<ActionConfig, String>) -> Binding<String> { Binding(get: { model.actions?[keyPath: key] ?? "" }, set: { model.actions?[keyPath: key] = $0 }) }
}
