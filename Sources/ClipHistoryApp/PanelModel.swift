import AppKit
import Foundation

enum PanelPage: Equatable {
    case list
    case settings
    case composer
    case actions

    var title: String {
        switch self {
        case .list: return "剪贴板记录"
        case .settings: return "设置"
        case .composer: return "快捷回复与编辑"
        case .actions: return "动作工坊"
        }
    }
}

struct PasteTargetInfo: Equatable {
    let name: String
    let bundleID: String
    let icon: NSImage?

    static func == (lhs: PasteTargetInfo, rhs: PasteTargetInfo) -> Bool {
        lhs.name == rhs.name && lhs.bundleID == rhs.bundleID
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var page: PanelPage = .list
    @Published var attachStatus: String?
    @Published var query = "" {
        didSet {
            if query != oldValue {
                reload()
            }
        }
    }
    @Published var items: [ClipItem] = []
    @Published var selectedID: ClipItem.ID? {
        didSet {
            if selectedID != oldValue {
                onSelectionChanged()
            }
        }
    }
    @Published var accessibilityTrusted = true
    /// Active category filter; `nil` means "全部".
    @Published var category: ClipCategory? {
        didSet {
            if category != oldValue { applyFilter() }
        }
    }
    /// Active smart archive filter; `nil` means all tags.
    @Published var smartTagFilter: SmartArchiveTag? {
        didSet {
            if smartTagFilter != oldValue { applyFilter() }
        }
    }
    /// Count of items per category for the filter bar badges.
    @Published var counts: [ClipCategory: Int] = [:]
    /// Count of items per smart archive tag.
    @Published var smartTagCounts: [SmartArchiveTag: Int] = [:]
    /// Total count across all categories for the current query.
    @Published var totalMatchingCount: Int = 0

    /// Item currently being edited in the composer page (`nil` means creating a new snippet).
    @Published var editingItem: ClipItem?

    /// Information about the target app that will receive `⌘V`.
    @Published var pasteTargetInfo: PasteTargetInfo?

    /// Incremented whenever the search bar should acquire keyboard focus.
    @Published var searchFocusTrigger: Int = 0

    /// Incremented only when the list should programmatically scroll to `selectedID` (e.g. keyboard arrows).
    @Published var scrollTrigger: Int = 0

    /// Whether the entire store has any items at all (used to distinguish empty DB from empty filter).
    @Published var hasAnyStoredItems: Bool = false

    // MARK: - Jev & Smart Reply Recommendation State
    @Published var recommendedReply: ClipItem?
    @Published var replyConfidence: Double = 0
    @Published var isJevRecommended: Bool = false
    @Published var suggestedActionID: String?
    @Published var latestCopiedTriggerText: String?

    // MARK: - Instant Translation & Action State
    @Published var translatedText: String?
    @Published var translatedForItemID: Int64?
    @Published var isRunningAction: Bool = false

    /// Whether clipboard recording is temporarily paused for privacy.
    @Published var isRecordingPaused: Bool = AppSettings.shared.isRecordingPaused
    var onPauseStateChange: (() -> Void)?

    /// Transient toast notification state.
    @Published var toastMessage: String?
    @Published var toastSymbol: String = "checkmark.circle.fill"
    private var toastTask: Task<Void, Never>?

    private var allItems: [ClipItem] = []

    let store: Store

    init(store: Store) {
        self.store = store
    }

    func reload() {
        isRecordingPaused = AppSettings.shared.isRecordingPaused
        allItems = (try? store.items(query: query)) ?? []
        hasAnyStoredItems = ((try? store.totalCount()) ?? 0) > 0
        totalMatchingCount = allItems.count
        counts = allItems.reduce(into: [:]) { result, item in
            result[item.category, default: 0] += 1
        }
        smartTagCounts = allItems.reduce(into: [:]) { result, item in
            if item.smartTag != .general {
                result[item.smartTag, default: 0] += 1
            }
        }
        // Only auto-clear smartTagFilter when query is empty and the last item with that tag was deleted.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let smartTagFilter,
           (smartTagCounts[smartTagFilter] ?? 0) == 0 {
            self.smartTagFilter = nil
        }
        applyFilter()
    }

    var availableCategories: [ClipCategory] {
        ClipCategory.allCases
    }

    var availableSmartTags: [SmartArchiveTag] {
        SmartArchiveTag.allCases.filter {
            $0 != .general && ((smartTagCounts[$0] ?? 0) > 0 || $0 == smartTagFilter)
        }
    }

    func cycleCategory(_ delta: Int) {
        let options: [ClipCategory?] = [nil] + availableCategories.map { Optional($0) }
        guard options.count > 1 else { return }
        let currentIndex = options.firstIndex(where: { $0 == category }) ?? 0
        let nextIndex = (currentIndex + delta + options.count) % options.count
        category = options[nextIndex]
    }

    private func applyFilter() {
        var filtered = allItems
        if let category {
            filtered = filtered.filter { $0.category == category }
        }
        if let smartTagFilter {
            filtered = filtered.filter { $0.smartTag == smartTagFilter }
        }

        // Apply `chinese-ime-lm` inspired Two-Tier Ranker (Exact-match guardrail + N-gram + Habit score)
        items = SmartRanker.rankItems(
            filtered,
            query: query,
            targetAppBundleID: pasteTargetInfo?.name
        )

        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = items.first?.id
    }

    private func onSelectionChanged() {
        if selectedID != translatedForItemID {
            translatedText = nil
            translatedForItemID = nil
        }
    }

    func clearTranslatedResult() {
        translatedText = nil
        translatedForItemID = nil
    }

    func saveTransformedAsHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let saved = try? store.recordHistory(trimmed) {
            reload()
            selectedID = saved.id
            requestScrollToSelection()
            showToast("已保存转换结果为新记录", symbol: "plus.circle.fill")
        }
    }

    func handleNewlyCopiedItem(_ item: ClipItem) {
        let snippets = (try? store.snippets()) ?? []
        SmartService.shared.evaluateCopiedItem(
            item,
            snippets: snippets,
            onLocalDecision: { [weak self] decision in
                self?.applyDecision(decision, for: item, snippets: snippets)
            },
            onJevDecision: { [weak self] decision in
                self?.applyDecision(decision, for: item, snippets: snippets)
            }
        )
    }

    private func applyDecision(_ decision: JevDecisionResult, for item: ClipItem, snippets: [ClipItem]) {
        if decision.archiveTag != item.smartTag {
            try? store.updateSmartTag(id: item.id, tag: decision.archiveTag)
            reload()
        }
        suggestedActionID = decision.suggestedActionID
        if let replyID = decision.recommendedReplyID,
           decision.replyConfidence >= 0.50,
           let matched = snippets.first(where: { $0.id == replyID }) {
            recommendedReply = matched
            replyConfidence = decision.replyConfidence
            isJevRecommended = decision.isFromJevModel
            latestCopiedTriggerText = item.displayTitle
        } else {
            recommendedReply = nil
            replyConfidence = 0
            isJevRecommended = false
        }
    }

    func dismissRecommendedReply() {
        recommendedReply = nil
        replyConfidence = 0
    }

    func refreshAccess() {
        accessibilityTrusted = PasteService.isTrusted(prompt: false)
    }

    func updatePasteTarget(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated else {
            pasteTargetInfo = nil
            return
        }
        let name = app.localizedName ?? "目标应用"
        let bundleID = app.bundleIdentifier ?? ""
        pasteTargetInfo = PasteTargetInfo(name: name, bundleID: bundleID, icon: app.icon)
    }

    func requestSearchFocus() {
        searchFocusTrigger &+= 1
    }

    func requestScrollToSelection() {
        scrollTrigger &+= 1
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
        requestScrollToSelection()
    }

    var selectedItem: ClipItem? {
        items.first(where: { $0.id == selectedID })
    }

    func togglePin(_ item: ClipItem) {
        let willPin = !item.isPinned
        try? store.togglePin(id: item.id)
        reload()
        showToast(willPin ? "已置顶" : "已取消置顶", symbol: willPin ? "pin.fill" : "pin.slash")
    }

    func convertToSnippet(_ item: ClipItem) {
        guard item.contentType != .image else { return }
        if item.kind == .snippet {
            _ = try? store.updateItem(id: item.id, title: item.title, body: item.body, kind: .history)
            reload()
            showToast("已转为普通历史", symbol: "clock.arrow.circlepath")
        } else {
            _ = try? store.convertToSnippet(id: item.id, title: item.title)
            reload()
            showToast("已保存为快捷回复", symbol: "text.bubble.fill")
        }
    }

    func openNewSnippet() {
        editingItem = nil
        page = .composer
    }

    func openEdit(_ item: ClipItem) {
        editingItem = item
        page = .composer
    }

    func delete(_ item: ClipItem) {
        let currentIndex = items.firstIndex(where: { $0.id == item.id })
        try? store.delete(id: item.id)
        reload()
        if let currentIndex, !items.isEmpty {
            let nextIdx = min(currentIndex, items.count - 1)
            selectedID = items[nextIdx].id
        } else {
            selectedID = items.first?.id
        }
        showToast("已删除条目", symbol: "trash")
    }

    func clearUnpinned() {
        try? store.clearUnpinnedHistory()
        reload()
        showToast("已清空未置顶历史", symbol: "sparkles")
    }

    func toggleRecordingPaused() {
        setRecordingPaused(!isRecordingPaused)
    }

    func setRecordingPaused(_ paused: Bool) {
        AppSettings.shared.isRecordingPaused = paused
        isRecordingPaused = paused
        onPauseStateChange?()
        showToast(
            paused ? "已暂停记录剪贴板（保护隐私）" : "已恢复记录剪贴板",
            symbol: paused ? "pause.circle.fill" : "play.circle.fill"
        )
    }

    func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        toastTask?.cancel()
        toastSymbol = symbol
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            self.toastMessage = nil
        }
    }
}
