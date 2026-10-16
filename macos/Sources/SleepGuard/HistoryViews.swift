import SwiftUI

struct HistoryPage: View {
    @ObservedObject var history: HistoryModel
    let stateDirectory: String
    var logFailure: String?
    @ViewState private var jumpPage = "1"
    private var jumpTarget: Int? {
        guard let page = Int(jumpPage), (1...history.pageCount).contains(page) else { return nil }
        return page
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeading(title: "事件历史", detail: "按时间倒序 · 同轮通知合并显示") {
                    RefreshButton(isRefreshing: history.loading, help: "刷新并查看最新历史") { await history.refresh() }
                }
                Picker("事件分类", selection: Binding(get: { history.category }, set: { value in Task { await history.selectCategory(value) } })) {
                    ForEach(HistoryCategory.allCases) { category in Text(category.title).tag(category) }
                }.pickerStyle(.segmented).labelsHidden().disabled(history.loading)
                HStack {
                    Text(history.rangeText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("每页", selection: Binding(get: { history.result.pageSize }, set: { value in Task { await history.setPageSize(value) } })) {
                        ForEach([20, 50, 100], id: \.self) { size in Text("\(size) 组").tag(size) }
                    }.fixedSize().disabled(history.loading)
                }
                if let failure = history.failure { QuietNotice(text: failure, warning: true) }
                if let logFailure { QuietNotice(text: logFailure, warning: true) }
            }.frame(maxWidth: 760).padding(20).frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !history.loaded && history.loading {
                        ProgressView("正在读取历史…").frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if history.groups.isEmpty && history.failure == nil {
                        EmptyStateRow(icon: "clock.arrow.circlepath", title: history.category == .all ? "暂无事件" : "此分类暂无事件", detail: "通知、暂停和处理记录会显示在对应分类中。")
                    }
                    ForEach(history.groups) { group in
                        HistoryEventRow(group: group)
                        Divider()
                    }
                    ExpandableSection("日志与数据") {
                        SectionBox {
                            FileLocationRow(title: "运行日志", path: stateDirectory + "/agent.log", openFile: true)
                            Divider()
                            FileLocationRow(title: "事件数据库", path: stateDirectory + "/state.db")
                        }.padding(.top, 10)
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: 760, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }.id("\(history.category.rawValue)-\(history.result.page)-\(history.result.pageSize)")
            Divider()
            pagination.frame(maxWidth: 760).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity)
        }
        .task { await history.loadIfNeeded() }
        .onChange(of: history.result.page) { jumpPage = String($0) }
    }
    private var pagination: some View {
        HStack(spacing: 8) {
            pageButton("第一页", icon: "chevron.left.2", target: 1, disabled: history.result.page == 1)
            pageButton("上一页", icon: "chevron.left", target: history.result.page - 1, disabled: history.result.page == 1)
            Text("第 \(history.result.page) / \(history.pageCount) 页").font(.caption).monospacedDigit().fixedSize()
            pageButton("下一页", icon: "chevron.right", target: history.result.page + 1, disabled: history.result.page == history.pageCount)
            pageButton("最后一页", icon: "chevron.right.2", target: history.pageCount, disabled: history.result.page == history.pageCount)
            Spacer(minLength: 8)
            TextField("页码", text: $jumpPage).textFieldStyle(.roundedBorder).frame(width: 52)
                .accessibilityLabel("跳转页码").onSubmit(jump).disabled(history.loading)
            Button("前往", action: jump).disabled(history.loading || jumpTarget == nil || jumpTarget == history.result.page)
        }
    }
    private func pageButton(_ title: String, icon: String, target: Int, disabled: Bool) -> some View {
        Button { Task { await history.go(to: target) } } label: { Image(systemName: icon).frame(width: 16) }
            .help(title).accessibilityLabel(title).disabled(disabled || history.loading)
    }
    private func jump() { if let page = jumpTarget { Task { await history.go(to: page) } } }
}

struct HistoryEventRow: View {
    let group: HistoryGroup
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(ClockText.historyTime(group.events[0].at)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title).font(.headline)
                if let label = group.events[0].label, !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                ForEach(group.events) { event in
                    if let delivery = event.delivery {
                        Label("\(delivery.channelName) · \(delivery.message)", systemImage: delivery.success ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.caption).foregroundStyle(delivery.success ? Color.green : Color.orange).textSelection(.enabled)
                    } else { Text(event.displayMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 5)
    }
}
