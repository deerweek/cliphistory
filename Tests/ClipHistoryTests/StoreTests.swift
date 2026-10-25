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
            ("贴边时不超出屏幕", testSnapClampsInsideScreen),
            ("链接识别", testLinkClassification),
            ("记录链接会标为链接类型", testRecordHistoryTagsLinks),
            ("记录图片并去重", testRecordImageStoresAndDeduplicates),
            ("图片字节可完整读回", testImageBytesRoundTrip),
            ("按分类筛选", testItemsFilterByCategory),
            ("分类计数", testCategoryCounts),
            ("分类归属推导", testCategoryDerivation),
            ("外观设置可持久化并限制透明度", testAppearanceSettingsPersistAndClamp),
            ("编辑条目与历史转快捷回复", testUpdateItemAndConvertToSnippet),
            ("快速统计总条数", testTotalCount),
            ("代码、颜色值与域名识别", testSmartContentClassifiers),
            ("智能语义归档与使用频次统计", testSmartArchiveAndUseCount),
            ("输入法短码精确命中保护与重排", testSmartRankerExactMatchGuardrailAndReply),
            ("动作工坊内置转换与动态模板展开", testClipActionEngineAndTemplates),
            ("图片 OCR 文字索引与搜索", testImageOCRIndexingAndSearch),
            ("验证码与单号智能提取", testCredentialCodeExtraction),
            ("JSON 备份导出与去重导入", testBackupExportAndImport)
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

private func testSmartArchiveAndUseCount() throws {
    try withStore { store in
        let addr = try store.recordHistory("收件人：张三 北京市海淀区中关村南大街 1 号 联系电话 13800138000", sourceApp: "微信", now: Date(timeIntervalSince1970: 1000))
        try expectEqual(addr.smartTag, .addressContact)
        try expectEqual(addr.sourceApp, "微信")
        try expectEqual(addr.useCount, 0)

        try store.recordUse(id: addr.id, now: Date(timeIntervalSince1970: 5000))
        try store.recordUse(id: addr.id, now: Date(timeIntervalSince1970: 6000))
        let updated = try store.items(smartTag: .addressContact).first
        try expectEqual(updated?.useCount, 2)
        try expectEqual(updated?.updatedAt, Date(timeIntervalSince1970: 1000))
        try expect(try store.hasHistoryItem(body: addr.body), "应检测到已存在的文本历史")

        // Multi-token search across source_app and body
        let multiSearch = try store.items(query: "微信 海淀")
        try expectEqual(multiSearch.map(\.id), [addr.id])

        // Brand-new copied item stays #1 in empty-query ranker even when older item has higher useCount
        let newest = try store.recordHistory("刚刚复制的新内容", sourceApp: "Safari", now: Date(timeIntervalSince1970: 2000))
        let rankedDefault = SmartRanker.rankItems(try store.items(), query: "", targetAppBundleID: "微信")
        try expectEqual(rankedDefault.first?.id, newest.id)

        let foreign = try store.recordHistory("Please let me know when the invoice is ready for review.")
        try expectEqual(foreign.smartTag, .foreignText)
        try expect(foreign.isForeignLanguage, "英文长句应被识别为外文")

        let otp = try store.recordHistory("【顺丰速运】您的取件验证码为 839201，请凭此码取件。")
        try expectEqual(otp.smartTag, .credential)
    }
}

private func testSmartRankerExactMatchGuardrailAndReply() throws {
    try withStore { store in
        let s1 = try store.addSnippet(
            title: "公司发票抬头",
            body: "名称：未来科技有限公司\n税号：91310000XXXXXX",
            triggerCode: ";fp"
        )
        let s2 = try store.addSnippet(
            title: "收货地址",
            body: "上海市徐汇区漕河泾开发区 88 号，手机 13912345678",
            triggerCode: ";dz"
        )

        let all = try store.items()
        let rankedByCode = SmartRanker.rankItems(all, query: ";dz")
        try expectEqual(rankedByCode.first?.id, s2.id)

        // Test contextual reply recommendation when copying a question
        let snippets = try store.snippets()
        let rec = SmartRanker.localRecommendReply(
            for: "你好，麻烦发一下你们公司的开票税号和发票抬头",
            snippets: snippets
        )
        try expectEqual(rec?.snippet.id, s1.id)
        try expect((rec?.confidence ?? 0) >= 0.60, "发票提问应高置信度匹配发票快捷回复")
    }
}

private func testClipActionEngineAndTemplates() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let expanded = ClipActionEngine.expandTemplateVariables(
        in: "日期:{{date}} 剪贴板:{{clipboard}}",
        currentClipboard: "测试词",
        now: fixedDate
    )
    try expect(expanded.contains("剪贴板:测试词"), "应展开 clipboard 占位符")
    try expect(!expanded.contains("{{date}}"), "应展开 date 占位符")

    let extracted = ClipActionEngine.runBuiltIn(
        id: "extract_digits",
        on: "您的登录验证码是 492817，5分钟内有效。"
    )
    try expectEqual(extracted, "492817")

    let formattedJSON = ClipActionEngine.runBuiltIn(
        id: "format_json",
        on: "{\"b\":1,\"a\":2}"
    )
    try expect(formattedJSON?.contains("\n") == true, "JSON 应被多行美化")
}

private func testAppearanceSettingsPersistAndClamp() throws {
    let suiteName = "ClipHistoryTests-Settings-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw Expectation(description: "无法创建测试偏好域")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    try expectEqual(settings.panelAccent, .system)
    try expectEqual(settings.panelDensity, .comfortable)
    try expectEqual(settings.panelOpacity, AppSettings.defaultPanelOpacity)
    try expectEqual(settings.showPreviewPane, true)

    settings.panelAccent = .purple
    settings.panelDensity = .compact
    settings.panelOpacity = 0.73
    settings.showPreviewPane = false
    let reloaded = AppSettings(defaults: defaults)
    try expectEqual(reloaded.panelAccent, .purple)
    try expectEqual(reloaded.panelDensity, .compact)
    try expectEqual(reloaded.panelOpacity, 0.73)
    try expectEqual(reloaded.showPreviewPane, false)

    reloaded.panelOpacity = 0.1
    try expectEqual(reloaded.panelOpacity, 0.55)
    reloaded.panelOpacity = 2
    try expectEqual(reloaded.panelOpacity, 1.0)
}

private func testUpdateItemAndConvertToSnippet() throws {
    try withStore { store in
        let history = try store.recordHistory("原始文本", now: Date(timeIntervalSince1970: 10))
        try expectEqual(history.kind, .history)
        try expectEqual(history.title, nil)

        let edited = try store.updateItem(
            id: history.id,
            title: "常用抬头",
            body: "https://github.com/deerweek",
            triggerCode: ";gh",
            now: Date(timeIntervalSince1970: 20)
        )
        try expectEqual(edited.title, "常用抬头")
        try expectEqual(edited.body, "https://github.com/deerweek")
        try expectEqual(edited.contentType, .link)
        try expectEqual(edited.triggerCode, ";gh")
        try expectEqual(edited.kind, .history)

        let promoted = try store.convertToSnippet(id: history.id, now: Date(timeIntervalSince1970: 30))
        try expectEqual(promoted.kind, .snippet)
        try expectEqual(promoted.category, .snippet)
        try expectEqual(promoted.title, "常用抬头")
    }
}

private func testTotalCount() throws {
    try withStore { store in
        try expectEqual(try store.totalCount(), 0)
        _ = try store.recordHistory("第一条")
        _ = try store.addSnippet(title: "标题", body: "第二条")
        try expectEqual(try store.totalCount(), 2)
    }
}

private func testSmartContentClassifiers() throws {
    try expect(ContentClassifier.isCodeLike("func hello() {\n    let x = 1\n    return x\n}"), "Swift 代码应被识别")
    try expect(ContentClassifier.isCodeLike("{\"name\": \"clip\", \"version\": 2}"), "JSON 应被识别")
    try expect(!ContentClassifier.isCodeLike("今天下午三点开会"), "普通自然语言不应被识别为代码")

    let hex = ContentClassifier.extractHexColor("#3B82F6")
    try expectEqual(hex?.hex, "#3B82F6")
    let shortHex = ContentClassifier.extractHexColor("#f0a")
    try expectEqual(shortHex?.hex, "#FF00AA")
    try expect(ContentClassifier.extractHexColor("not a color") == nil, "非颜色值应返回 nil")

    try expectEqual(ContentClassifier.extractHost("https://www.github.com/deerweek/cliphistory"), "github.com")
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

private func testLinkClassification() throws {
    let links = [
        "https://example.com",
        "http://example.com/path?q=1",
        "https://github.com/deerweek/cliphistory",
        "github.com",
        "example.co.uk/a/b",
        "mailto:hi@example.com"
    ]
    for link in links {
        try expectEqual(ContentClassifier.classify(link), .link)
    }
    let notLinks = [
        "普通的一段文字",
        "hello world",
        "看看 https://example.com 这个",
        "just.a.sentence with spaces",
        "file",
        "3.14"
    ]
    for text in notLinks {
        try expectEqual(ContentClassifier.classify(text), .text)
    }
}

private func testRecordHistoryTagsLinks() throws {
    try withStore { store in
        let link = try store.recordHistory("https://example.com")
        let text = try store.recordHistory("只是一句话")
        try expectEqual(link.contentType, .link)
        try expectEqual(link.category, .link)
        try expectEqual(text.contentType, .text)
        try expectEqual(text.category, .text)
    }
}

private func testRecordImageStoresAndDeduplicates() throws {
    try withStore { store in
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        let first = try store.recordImage(png, width: 800, height: 600, now: Date(timeIntervalSince1970: 1))
        try expectEqual(first.contentType, .image)
        try expectEqual(first.category, .image)
        try expectEqual(first.displayTitle, "图片 · 800×600")

        _ = try store.recordHistory("中间", now: Date(timeIntervalSince1970: 2))
        let again = try store.recordImage(png, width: 800, height: 600, now: Date(timeIntervalSince1970: 3))
        try expectEqual(again.id, first.id)

        let items = try store.items()
        try expectEqual(items.count, 2)
        try expectEqual(items.first?.id, first.id)
    }
}

private func testImageBytesRoundTrip() throws {
    try withStore { store in
        let png = Data((0..<256).map { UInt8($0 & 0xFF) })
        let saved = try store.recordImage(png, width: 1, height: 1)
        let fetched = try store.items(category: .image).first
        try expectEqual(fetched?.imageData, png)
        try expectEqual(saved.imageData, png)
    }
}

private func testItemsFilterByCategory() throws {
    try withStore { store in
        _ = try store.recordHistory("纯文本", now: Date(timeIntervalSince1970: 1))
        _ = try store.recordHistory("https://example.com", now: Date(timeIntervalSince1970: 2))
        _ = try store.addSnippet(title: "回复", body: "你好", now: Date(timeIntervalSince1970: 3))
        _ = try store.recordImage(Data([1, 2, 3]), width: 10, height: 10, now: Date(timeIntervalSince1970: 4))

        try expectEqual(try store.items(category: .text).map(\.body), ["纯文本"])
        try expectEqual(try store.items(category: .link).map(\.body), ["https://example.com"])
        try expectEqual(try store.items(category: .snippet).map(\.body), ["你好"])
        try expectEqual(try store.items(category: .image).count, 1)
        try expectEqual(try store.items().count, 4)
    }
}

private func testCategoryCounts() throws {
    try withStore { store in
        _ = try store.recordHistory("文本一")
        _ = try store.recordHistory("文本二")
        _ = try store.recordHistory("https://a.com")
        _ = try store.addSnippet(title: nil, body: "回复内容")
        _ = try store.recordImage(Data([9]), width: 4, height: 4)

        let counts = try store.categoryCounts()
        try expectEqual(counts[.text], 2)
        try expectEqual(counts[.link], 1)
        try expectEqual(counts[.snippet], 1)
        try expectEqual(counts[.image], 1)
    }
}

private func testCategoryDerivation() throws {
    let image = ClipItem(id: 1, kind: .history, contentType: .image, body: "图片",
                         title: nil, isPinned: false, createdAt: Date(), updatedAt: Date())
    let snippetLink = ClipItem(id: 2, kind: .snippet, contentType: .link, body: "https://x.com",
                               title: nil, isPinned: false, createdAt: Date(), updatedAt: Date())
    let link = ClipItem(id: 3, kind: .history, contentType: .link, body: "https://x.com",
                        title: nil, isPinned: false, createdAt: Date(), updatedAt: Date())
    let text = ClipItem(id: 4, kind: .history, contentType: .text, body: "hi",
                        title: nil, isPinned: false, createdAt: Date(), updatedAt: Date())
    try expectEqual(image.category, .image)
    try expectEqual(snippetLink.category, .snippet)
    try expectEqual(link.category, .link)
    try expectEqual(text.category, .text)
}

private func testImageOCRIndexingAndSearch() throws {
    try withStore { store in
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0A])
        let img = try store.recordImage(png, width: 1280, height: 720)
        try expectEqual(img.imageDimensionsLabel, "图片 · 1280×720")
        try expect(img.imageOCRText == nil, "初始无 OCR 文字")

        try store.updateImageOCRText(id: img.id, ocrText: "发票号码 98765432\n校验码 ABCD")
        let matched = try store.items(query: "98765432")
        try expectEqual(matched.count, 1)
        try expectEqual(matched.first?.id, img.id)
        try expectEqual(matched.first?.imageDimensionsLabel, "图片 · 1280×720")
        try expectEqual(matched.first?.imageOCRText, "发票号码 98765432\n校验码 ABCD")
        try expect(matched.first?.secondaryPreviewText.contains("发票号码 98765432") == true, "副标题预览包含 OCR 文字")
    }
}

private func testCredentialCodeExtraction() throws {
    try withStore { store in
        let otp = try store.recordHistory("【阿里云】您的验证码为 839204，请在 5 分钟内完成验证。")
        try expectEqual(otp.smartTag, .credential)
        try expectEqual(otp.extractedCredentialCode, "839204")
    }
}

private func testBackupExportAndImport() throws {
    try withStore { sourceStore in
        _ = try sourceStore.addSnippet(title: "公司地址", body: "北京市朝阳区", triggerCode: ";dz", smartTag: .addressContact)
        let pinned = try sourceStore.recordHistory("重要置顶笔记", sourceApp: "备忘录")
        try sourceStore.setPinned(id: pinned.id, pinned: true)

        let customActions = [
            ClipActionDescriptor(id: "custom_1", title: "测试动作", symbolName: "sparkles", kind: .aiPrompt, payload: "prompt")
        ]
        let backupData = try sourceStore.exportBackup(actions: customActions)

        try withStore { destStore in
            let firstImport = try destStore.importBackup(backupData)
            try expectEqual(firstImport.importedCount, 2)
            try expectEqual(firstImport.actions?.first?.title, "测试动作")

            let items = try destStore.items()
            try expectEqual(items.count, 2)
            try expect(items.contains(where: { $0.triggerCode == ";dz" && $0.kind == .snippet }), "快捷回复短码保留")
            try expect(items.contains(where: { $0.body == "重要置顶笔记" && $0.isPinned }), "置顶历史保留")
        }
    }
}
