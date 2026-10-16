import Combine
import Foundation

enum HistoryCategory: String, CaseIterable, Identifiable, Sendable {
    case all, monitor, notification, action, control, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .monitor: "监控"
        case .notification: "通知"
        case .action: "应用处理"
        case .control: "暂停与屏幕"
        case .other: "其他"
        }
    }
}

struct HistoryQuery: Sendable {
    var category: HistoryCategory
    var page = 1
    var pageSize = 20
    var snapshotId: Int64 = 0
    var arguments: [String] {
        ["ui", "history", "--category", category.rawValue, "--page", String(page),
         "--page-size", String(pageSize), "--snapshot-id", String(snapshotId)]
    }
}

struct HistoryResult: Decodable, Sendable {
    var events: [HistoryEvent] = []
    var page = 1
    var pageSize = 20
    var total = 0
    var snapshotId: Int64 = 0
}

@MainActor final class HistoryModel: ObservableObject {
    @Published private(set) var category: HistoryCategory = .all
    @Published private(set) var result = HistoryResult()
    @Published private(set) var groups: [HistoryGroup] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var failure: String?
    private let fetch: @Sendable (HistoryQuery) async throws -> HistoryResult

    init(fetch: @escaping @Sendable (HistoryQuery) async throws -> HistoryResult) { self.fetch = fetch }

    var pageCount: Int { max(1, (result.total + result.pageSize - 1) / result.pageSize) }
    var rangeText: String {
        guard result.total > 0 else { return "共 0 组记录" }
        let first = (result.page - 1) * result.pageSize + 1
        return "第 \(first)–\(min(first + result.pageSize - 1, result.total)) 组，共 \(result.total) 组"
    }
    func loadIfNeeded() async { if !loaded { await refresh() } }
    func refreshIfAtLatest() async { if result.page == 1 { await refresh() } }
    func refresh() async { await load(HistoryQuery(category: category, pageSize: result.pageSize)) }
    func selectCategory(_ category: HistoryCategory) async {
        guard category != self.category else { return }
        await load(HistoryQuery(category: category, pageSize: result.pageSize))
    }
    func setPageSize(_ size: Int) async {
        guard [20, 50, 100].contains(size), size != result.pageSize else { return }
        await load(HistoryQuery(category: category, pageSize: size))
    }
    func go(to page: Int) async {
        let page = min(max(1, page), pageCount)
        guard page != result.page else { return }
        await load(HistoryQuery(category: category, page: page, pageSize: result.pageSize, snapshotId: result.snapshotId))
    }
    private func load(_ query: HistoryQuery) async {
        guard !loading else { return }
        loading = true; failure = nil
        defer { loading = false }
        do {
            let page = try await fetch(query)
            // Commit the controls and records together. A failed request leaves
            // the last successful category/page visible and available for retry.
            groups = HistoryGroup.grouped(page.events)
            result = page
            category = query.category
            loaded = true
        } catch { failure = "读取历史失败：\(error.localizedDescription)" }
    }
}
