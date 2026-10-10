import SwiftUI

struct RuleEditorItem: Identifiable {
    let id = UUID()
    var rule: AppRule
    var originalID: String?
}
struct RuleEditor: View {
    @ObservedObject var model: GuardModel
    let item: RuleEditorItem
    @Environment(\.dismiss) private var dismiss
    @ViewState private var rule: AppRule
    @ViewState private var selected = ""
    @ViewState private var group = "全部"
    @ViewState private var browserOpen: Bool
    @ViewState private var highlighted: String?
    @FocusState private var manualNameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var match = "bundle"
    @ViewState private var identity = ""
    @ViewState private var error: String?
    @ViewState private var search = ""
    init(model: GuardModel, item: RuleEditorItem) {
        self.model = model; self.item = item
        _rule = State(initialValue: item.rule)
        _selected = State(initialValue: item.originalID == nil ? "" : item.rule.id)
        _browserOpen = State(initialValue: item.originalID == nil)
        _match = State(initialValue: item.rule.bundleId.isEmpty && !item.rule.path.isEmpty ? "path" : "bundle")
        _identity = State(initialValue: item.rule.id)
    }
    private var chosen: CatalogApp? { model.catalog.first { $0.id == selected } }
    private var filteredCatalog: [CatalogApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.catalog.filter { (group == "全部" || $0.group == group) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleId.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)) }
    }
    private var protected: Bool { chosen?.protected ?? AppCatalog.protectedPath(match == "path" ? identity : "", bundleId: match == "bundle" ? identity : "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.originalID == nil ? "添加应用规则" : "编辑应用规则").font(.title2.weight(.semibold))
            HStack(spacing: 10) {
                Button {
                    if selected == "manual" { selected = ""; identity = "" }
                    browserOpen.toggle(); highlighted = nil
                } label: {
                    HStack(spacing: 10) {
                        if let chosen { AppIcon(path: chosen.appPath) }
                        Text(selected == "manual" ? "手动填写" : identity.isEmpty ? "选择应用…" : rule.label).lineLimit(1)
                        Spacer(minLength: 10)
                        Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary).rotationEffect(.degrees(browserOpen ? 180 : 0))
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                }.buttonStyle(HoverButtonStyle(selected: browserOpen)).accessibilityLabel("选择应用")
                Button(selected == "manual" ? "从列表选择" : "手动填写") {
                    if selected == "manual" { selected = ""; identity = ""; browserOpen = true }
                    else { selected = "manual"; identity = ""; rule.name = ""; match = "bundle"; browserOpen = false; manualNameFocused = true }
                }.controlSize(.small)
            }
            if selected != "manual" {
                if browserOpen {
                    AppSearchField(text: $search, focus: browserOpen, navigate: navigate, select: selectHighlighted, cancel: { browserOpen = false })
                        .frame(height: 24)
                    Picker("应用分类", selection: $group) { ForEach(["全部", "已启动", "后台任务", "未启动"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    ScrollViewReader { scroll in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(["已启动", "后台任务", "未启动"], id: \.self) { category in
                                    let apps = filteredCatalog.filter { $0.group == category }
                                    if !apps.isEmpty {
                                        Text(category).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 8)
                                        ForEach(apps) { app in
                                            Button { choose(app) } label: {
                                                HStack(spacing: 10) {
                                                    AppIcon(path: app.appPath)
                                                    VStack(alignment: .leading, spacing: 3) { Text(app.name).lineLimit(1); Text(app.bundleId.isEmpty ? app.path : app.bundleId).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                                    Spacer(); if selected == app.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                                }.padding(9).contentShape(Rectangle())
                                            }.buttonStyle(HoverButtonStyle(selected: selected == app.id || highlighted == app.id)).id(app.id)
                                        }
                                    }
                                }
                                if model.catalogLoading { ProgressView("正在读取应用…").controlSize(.small).padding(12) }
                                else if filteredCatalog.isEmpty { Text("没有找到应用，可换个名称或手动填写。").font(.caption).foregroundStyle(.secondary).padding(12) }
                            }
                        }.frame(height: 220).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                            .onChange(of: highlighted) { id in if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { scroll.scrollTo(id) } } }
                    }
                }
                if !identity.isEmpty { Text(identity).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
            } else {
                LabeledContent("显示名称") { TextField("例如：网易云音乐", text: $rule.name).focused($manualNameFocused) }
                Picker("匹配方式", selection: $match) { Text("Bundle ID").tag("bundle"); Text("可执行文件路径").tag("path") }.pickerStyle(.segmented)
                TextField(match == "bundle" ? "com.example.app" : "/Applications/Example.app/Contents/MacOS/Example", text: $identity).accessibilityLabel(match == "bundle" ? "Bundle ID" : "可执行文件绝对路径")
            }
            Text("处理方式 · 可多选").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 22) { Toggle("通知", isOn: $rule.notify); Toggle("处理", isOn: $rule.process).disabled(protected) }.toggleStyle(.checkbox)
            Text(protected ? "此进程仅支持通知或忽略。" : "都不勾选即忽略。").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if let id = item.originalID { Button("删除规则", role: .destructive) { model.rules.removeAll { $0.id == id }; dismiss() } }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(item.originalID == nil ? "添加规则" : "保存规则") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480)
            .onChange(of: selected) { _ in
                if let chosen {
                    let notify = rule.notify, process = rule.process
                    rule = chosen.rule; identity = rule.id; match = rule.bundleId.isEmpty ? "path" : "bundle"
                    rule.notify = notify; rule.process = protected ? false : process
                }
                error = nil
            }
            .onChange(of: model.catalogLoading) { loading in
                if !loading, item.originalID != nil, chosen == nil { selected = "manual"; browserOpen = false }
            }
            .onChange(of: search) { _ in highlighted = nil }
            .onChange(of: group) { _ in highlighted = nil }
            .onChange(of: identity) { _ in if protected { rule.process = false } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: browserOpen)
            .onExitCommand { if browserOpen { browserOpen = false } else { dismiss() } }
    }
    private func choose(_ app: CatalogApp) { selected = app.id; browserOpen = false }
    private func selectHighlighted() {
        if let app = filteredCatalog.first(where: { $0.id == highlighted }) ?? filteredCatalog.first { choose(app) }
    }
    private func navigate(_ direction: Int) {
        let apps = filteredCatalog
        guard !apps.isEmpty else { return }
        if let index = apps.firstIndex(where: { $0.id == highlighted }) { highlighted = apps[(index + direction + apps.count) % apps.count].id }
        else { highlighted = direction > 0 ? apps.first?.id : apps.last?.id }
    }
    private func save() {
        guard !selected.isEmpty else { error = "请先选择应用。"; return }
        var result = rule
        let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        if chosen == nil { result.bundleId = match == "bundle" ? value : ""; result.path = match == "path" ? value : "" }
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty && !result.id.isEmpty else { error = "请填写显示名称和匹配标识。"; return }
        guard result.path.isEmpty || result.path.hasPrefix("/") else { error = "可执行文件路径必须以 / 开头。"; return }
        guard result.bundleId.isEmpty || result.bundleId.range(of: "^[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil else { error = "请输入有效的 Bundle ID，例如 com.example.app。"; return }
        guard !model.rules.contains(where: { $0.id != item.originalID && $0.id == result.id }) else { error = "这个应用已有规则，请编辑已有规则。"; return }
        if protected { result.process = false }
        if let index = model.rules.firstIndex(where: { $0.id == item.originalID }) { model.rules[index] = result }
        else { model.rules.append(result) }
        dismiss()
    }
}
struct ChannelEditorItem: Identifiable {
    let id = UUID()
    var channel: NotificationChannel
    var isNew: Bool
}
struct ChannelEditor: View {
    @ObservedObject var model: GuardModel
    let item: ChannelEditorItem
    @Environment(\.dismiss) private var dismiss
    @ViewState private var channel: NotificationChannel
    @ViewState private var chatId: String
    @ViewState private var token = ""
    @ViewState private var error: String?
    @ViewState private var saving = false
    init(model: GuardModel, item: ChannelEditorItem) {
        self.model = model; self.item = item
        _channel = State(initialValue: item.channel)
        _chatId = State(initialValue: item.channel.chatId == 0 ? "" : String(item.channel.chatId))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.isNew ? "添加通知渠道" : "配置通知渠道").font(.title2.weight(.semibold))
            Text("可以添加多个同类型渠道。").font(.caption).foregroundStyle(.secondary)
            Picker("渠道类型", selection: $channel.type) { ForEach(Provider.all) { provider in Text(provider.name + (provider.ready ? "" : " · 待接入")).tag(provider.id) } }.disabled(!item.isNew || saving)
            LabeledContent("渠道名称") { TextField("例如：电报 · 个人提醒", text: $channel.name) }
            if channel.ready {
                LabeledContent("Chat ID") { TextField("例如：-1001234567890", text: $chatId) }
                LabeledContent("Bot Token") { SecureField(item.isNew ? "填写 Bot Token" : "留空保留当前凭据", text: $token) }
                Text("Token 保存在 macOS 钥匙串。").font(.caption).foregroundStyle(.secondary)
                SectionBox { SwitchRow(title: "启用此渠道", isOn: $channel.enabled) }
            } else { QuietNotice(text: "尚未接入，可先保存此渠道。") }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if !item.isNew { Button("删除渠道", role: .destructive) { saving = true; Task { do { try await model.deleteChannel(channel); token = ""; dismiss() } catch { self.error = error.localizedDescription; saving = false } } } }
                Spacer(); Button("取消") { token = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Button(item.isNew ? "添加渠道" : "保存配置") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.disabled(saving || model.busy)
        }.padding(24).frame(width: 440)
            .onDisappear { token = "" }
            .onChange(of: channel.type) { _ in if !channel.ready { channel.enabled = false }; error = nil }
    }
    private func save() {
        channel.name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.name.isEmpty else { error = "请输入渠道名称。"; return }
        guard !model.channels.contains(where: { $0.id != channel.id && $0.name == channel.name }) else { error = "渠道名称已存在，请换一个名称。"; return }
        if channel.ready {
            guard let id = Int64(chatId), id != 0 else { error = "请输入有效的非零 Chat ID。"; return }; channel.chatId = id
            if channel.keychainService.isEmpty { channel.keychainService = "sleepguard.telegram." + channel.id }
            if item.isNew && token.isEmpty && channel.tokenEnv.isEmpty && !Keychain.contains(service: channel.keychainService) { error = "请填写 Bot Token。"; return }
        } else { channel.enabled = false; channel.chatId = 0; token = "" }
        saving = true
        Task { do { try await model.saveChannel(channel, token: token); token = ""; dismiss() } catch { self.error = error.localizedDescription; saving = false } }
    }
}
