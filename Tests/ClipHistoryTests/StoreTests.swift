import Foundation

@main
enum StoreTests {
    static func main() {
        let cases: [(String, () throws -> Void)] = [
            ("记录历史并按时间倒序", testRecordHistoryInsertsAndListsNewestFirst),
            ("相同内容去重并移到最前", testRecordHistoryDeduplicatesAndMovesExistingToFront),
            ("快捷回复与历史分开保存", testAddSnippetStaysSeparateFromHistory),
            ("列表顺序：置顶、回复、历史", testListPutsPinnedThenSnippetsThenHistory),
            ("置顶与搜索", testTogglePinAndSearchByTitleOrBody),
            ("按条数清理时保留置顶和回复", testCleanupByCountKeepsPinnedAndSnippets),
            ("按天数清理只删未置顶历史", testCleanupByAgeDeletesOldUnpinnedHistoryOnly),
            ("清空未置顶时保留置顶和回复", testClearUnpinnedHistoryKeepsPinnedAndSnippets),
            ("删除单条", testDeleteRemovesOnlyThatItem),
            ("展示标题优先用自定义标题", testDisplayTitlePrefersCustomTitle),
            ("面板优先贴在目标窗口右侧", testSnapPrefersRightOfTarget),
            ("右侧放不下时贴到左侧", testSnapMovesToLeftWhenRightSideIsBlocked),
            ("贴边时不超出屏幕", testSnapClampsInsideScreen)
        ]

        var failed = 0
        for (name, test) in cases {
            do {
                try test()
                print("通过  \(name)")
            } catch {
                failed += 1
                print("失败  \(name): \(error)")
            }
        }

        if failed > 0 {
            print("\(failed) 个测试失败")
            exit(1)
        }
        print("全部测试通过")
    }
}

private struct Expectation: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition {
        throw Expectation(description: "\(file):\(line) \(message)")
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: String = #fileID, line: Int = #line) throws {
    if lhs != rhs {
        throw Expectation(description: "\(file):\(line) 期望 \(rhs)，实际 \(lhs)")
    }
}

private func withStore(_ body: (Store) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipHistoryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try Store(path: directory.appendingPathComponent("history.sqlite").path)
    try body(store)
}

private func testRecordHistoryInsertsAndListsNewestFirst() throws {
    try withStore { store in
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        _ = try store.recordHistory("较早", now: first)
        _ = try store.recordHistory("较新", now: second)

        let items = try store.items()
        try expectEqual(items.map(\.body), ["较新", "较早"])
        try expect(items.allSatisfy { $0.kind == .history }, "应全部是历史")
    }
}

private func testRecordHistoryDeduplicatesAndMovesExistingToFront() throws {
    try withStore { store in
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let third = Date(timeIntervalSince1970: 3_000)
        let original = try store.recordHistory("重复", now: first)
        _ = try store.recordHistory("中间", now: second)
        let moved = try store.recordHistory("重复", now: third)

        let items = try store.items()
        try expectEqual(items.count, 2)
        try expectEqual(moved.id, original.id)
        try expectEqual(items.map(\.body), ["重复", "中间"])
        try expectEqual(items[0].updatedAt, third)
    }
}

private func testAddSnippetStaysSeparateFromHistory() throws {
    try withStore { store in
        _ = try store.recordHistory("同一段文字", now: Date(timeIntervalSince1970: 1))
        _ = try store.addSnippet(title: "问候", body: "同一段文字", now: Date(timeIntervalSince1970: 2))

        let items = try store.items()
        try expectEqual(items.count, 2)
        try expectEqual(items[0].kind, .snippet)
        try expectEqual(items[0].title, "问候")
        try expectEqual(items[1].kind, .history)
    }
}

private func testListPutsPinnedThenSnippetsThenHistory() throws {
    try withStore { store in
        _ = try store.recordHistory("历史甲", now: Date(timeIntervalSince1970: 10))
        let historyB = try store.recordHistory("历史乙", now: Date(timeIntervalSince1970: 20))
        _ = try store.addSnippet(title: "回复", body: "你好", now: Date(timeIntervalSince1970: 30))
        try store.setPinned(id: historyB.id, pinned: true)

        try expectEqual(try store.items().map(\.body), ["历史乙", "你好", "历史甲"])
    }
}

private func testTogglePinAndSearchByTitleOrBody() throws {
    try withStore { store in
        let item = try store.addSnippet(title: "快递地址", body: "中山路 1 号", now: Date())
        try store.togglePin(id: item.id)
        try expect(try store.items().first?.isPinned == true, "应已置顶")
        try expectEqual(try store.items(query: "中山").map(\.title), ["快递地址"])
        try expectEqual(try store.items(query: "快递").count, 1)
        try expect(try store.items(query: "不存在").isEmpty, "无关搜索应为空")
    }
}

private func testCleanupByCountKeepsPinnedAndSnippets() throws {
    try withStore { store in
        let snippet = try store.addSnippet(title: "固定", body: "快捷回复", now: Date(timeIntervalSince1970: 1))
        let pinned = try store.recordHistory("置顶历史", now: Date(timeIntervalSince1970: 2))
        try store.setPinned(id: pinned.id, pinned: true)
        _ = try store.recordHistory("旧", now: Date(timeIntervalSince1970: 3))
        _ = try store.recordHistory("新", now: Date(timeIntervalSince1970: 4))

        try store.cleanup(maxHistory: 1, maxAgeDays: nil, now: Date(timeIntervalSince1970: 5))

        let bodies = try store.items().map(\.body)
        try expectEqual(Set(bodies), Set(["快捷回复", "置顶历史", "新"]))
        try expect(bodies.contains(snippet.body), "快捷回复应保留")
    }
}

private func testCleanupByAgeDeletesOldUnpinnedHistoryOnly() throws {
    try withStore { store in
        let now = Date(timeIntervalSince1970: 10 * 86_400)
        _ = try store.addSnippet(title: "旧回复", body: "还在", now: Date(timeIntervalSince1970: 0))
        let pinned = try store.recordHistory("旧但置顶", now: Date(timeIntervalSince1970: 0))
        try store.setPinned(id: pinned.id, pinned: true)
        _ = try store.recordHistory("该删", now: Date(timeIntervalSince1970: 0))
        _ = try store.recordHistory("还新", now: Date(timeIntervalSince1970: 9 * 86_400))

        try store.cleanup(maxHistory: nil, maxAgeDays: 2, now: now)
        try expectEqual(Set(try store.items().map(\.body)), Set(["还在", "旧但置顶", "还新"]))
    }
}

private func testClearUnpinnedHistoryKeepsPinnedAndSnippets() throws {
    try withStore { store in
        _ = try store.addSnippet(title: "回复", body: "在", now: Date())
        let pinned = try store.recordHistory("钉住", now: Date())
        try store.setPinned(id: pinned.id, pinned: true)
        _ = try store.recordHistory("清掉", now: Date())

        try store.clearUnpinnedHistory()
        try expectEqual(Set(try store.items().map(\.body)), Set(["在", "钉住"]))
    }
}

private func testDeleteRemovesOnlyThatItem() throws {
    try withStore { store in
        let keep = try store.recordHistory("留", now: Date())
        let gone = try store.recordHistory("走", now: Date())
        try store.delete(id: gone.id)
        try expectEqual(try store.items().map(\.id), [keep.id])
    }
}

private func testDisplayTitlePrefersCustomTitle() throws {
    let titled = ClipItem(
        id: 1,
        kind: .snippet,
        body: "正文很长",
        title: "短标题",
        isPinned: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    try expectEqual(titled.displayTitle, "短标题")
}

private func testSnapPrefersRightOfTarget() throws {
    let origin = PanelPlacement.snappedOrigin(
        panel: CGSize(width: 100, height: 80),
        target: CGRect(x: 100, y: 100, width: 400, height: 300),
        screen: CGRect(x: 0, y: 0, width: 1200, height: 800)
    )
    try expectEqual(origin, CGPoint(x: 508, y: 320))
}

private func testSnapMovesToLeftWhenRightSideIsBlocked() throws {
    let origin = PanelPlacement.snappedOrigin(
        panel: CGSize(width: 200, height: 80),
        target: CGRect(x: 700, y: 100, width: 250, height: 300),
        screen: CGRect(x: 0, y: 0, width: 1000, height: 800)
    )
    try expectEqual(origin, CGPoint(x: 492, y: 320))
}

private func testSnapClampsInsideScreen() throws {
    let origin = PanelPlacement.snappedOrigin(
        panel: CGSize(width: 100, height: 80),
        target: CGRect(x: 10, y: 10, width: 200, height: 40),
        screen: CGRect(x: 0, y: 0, width: 800, height: 600)
    )
    try expect(origin.y >= 0, "不应超出屏幕下沿")
    try expect(origin.x >= 0, "不应超出屏幕左沿")
    try expect(origin.x + 100 <= 800, "不应超出屏幕右沿")
}
