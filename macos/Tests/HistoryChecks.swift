import Foundation

actor HistoryFixture {
    var queries: [HistoryQuery] = []
    var shouldFail = false
    var total = 45
    func fail(_ fail: Bool) { shouldFail = fail }
    func retain(_ total: Int) { self.total = total }
    func fetch(_ query: HistoryQuery) throws -> HistoryResult {
        queries.append(query)
        if shouldFail { throw BackendFailure(message: "fixture failure") }
        let page = min(query.page, max(1, (total + query.pageSize - 1) / query.pageSize))
        return HistoryResult(events: [HistoryChecks.event(Int64(page))], page: page, pageSize: query.pageSize, total: total, snapshotId: query.snapshotId == 0 ? 100 : query.snapshotId)
    }
}

@main struct HistoryChecks {
    static func event(_ id: Int64, round: String? = nil, success: Bool = true) -> HistoryEvent {
        HistoryEvent(id: id, at: "2026-10-16T12:00:00Z", incident: "test", kind: round == nil ? "detected" : "notification_sent", message: "fixture",
                     delivery: round.map { Delivery(channelId: "test", channelName: "Test", provider: "test", roundId: $0, success: success, message: "fixture") })
    }
    @MainActor static func main() async throws {
        let fixture = HistoryFixture()
        let model = HistoryModel { try await fixture.fetch($0) }
        await model.loadIfNeeded()
        assert(model.loaded && model.result.page == 1 && model.pageCount == 3)
        await model.go(to: 2)
        var queries = await fixture.queries
        assert(queries.last?.page == 2 && queries.last?.snapshotId == 100)
        let count = queries.count
        await model.refreshIfAtLatest()
        queries = await fixture.queries
        assert(queries.count == count && model.result.page == 2, "automatic refresh moved an older page")
        await model.loadIfNeeded()
        queries = await fixture.queries
        assert(queries.count == count, "reopening history discarded the current page")

        await fixture.fail(true)
        await model.selectCategory(.notification)
        assert(model.failure != nil && model.category == .all && model.result.page == 2 && model.groups[0].id == 2, "a failed filter mislabeled existing records")
        await fixture.fail(false)
        await model.selectCategory(.notification)
        queries = await fixture.queries
        assert(model.failure == nil && model.category == .notification && model.result.page == 1)
        assert(queries.last?.snapshotId == 0)
        await model.go(to: 3)
        await fixture.retain(21)
        await model.go(to: 2)
        assert(model.result.page == 2 && model.pageCount == 2 && model.rangeText == "第 21–21 组，共 21 组")
        await model.refresh()
        queries = await fixture.queries
        assert(model.result.page == 1 && queries.last?.snapshotId == 0)
        await model.setPageSize(50)
        assert(model.result.pageSize == 50 && model.result.page == 1 && model.pageCount == 1)

        let groups = HistoryGroup.grouped([event(5, round: "mixed"), event(4, round: ""), event(3, round: "mixed", success: false), event(2, round: ""), event(1)])
        assert(groups.count == 4 && groups[0].events.map(\.id) == [5, 3] && groups[0].title == "通知 · 部分渠道失败")
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(HistoryResult.self, from: Data("{\"events\":[],\"page\":1,\"page_size\":20,\"total\":0,\"snapshot_id\":0}".utf8))
        assert(decoded.events.isEmpty && decoded.pageSize == 20)
        assert(HistoryQuery(category: .control, page: 2, pageSize: 50, snapshotId: 123).arguments == ["ui", "history", "--category", "control", "--page", "2", "--page-size", "50", "--snapshot-id", "123"])
        print("History checks passed: stable browsing, failure recovery, category/size resets, page bounds and notification grouping.")
    }
}
