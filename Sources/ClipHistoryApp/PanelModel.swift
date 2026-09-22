import Foundation

enum PanelPage: Equatable {
    case list
    case settings
    case composer

    var title: String {
        switch self {
        case .list: return "剪贴板记录"
        case .settings: return "设置"
        case .composer: return "添加快捷回复"
        }
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
    @Published var selectedID: ClipItem.ID?
    @Published var accessibilityTrusted = true
    /// Active category filter; `nil` means "全部".
    @Published var category: ClipCategory? {
        didSet {
            if category != oldValue { applyFilter() }
        }
    }
    /// Count of items per category for the filter bar badges.
    @Published var counts: [ClipCategory: Int] = [:]

    private var allItems: [ClipItem] = []

    let store: Store

    init(store: Store) {
        self.store = store
    }

    func reload() {
        allItems = (try? store.items(query: query)) ?? []
        counts = allItems.reduce(into: [:]) { result, item in
            result[item.category, default: 0] += 1
        }
        applyFilter()
    }

    /// Categories that currently have at least one item, in a stable order.
    var availableCategories: [ClipCategory] {
        ClipCategory.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    private func applyFilter() {
        if let category {
            items = allItems.filter { $0.category == category }
        } else {
            items = allItems
        }
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = items.first?.id
    }

    func refreshAccess() {
        accessibilityTrusted = PasteService.isTrusted(prompt: false)
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    var selectedItem: ClipItem? {
        items.first(where: { $0.id == selectedID })
    }

    func togglePin(_ item: ClipItem) {
        try? store.togglePin(id: item.id)
        reload()
    }

    func delete(_ item: ClipItem) {
        try? store.delete(id: item.id)
        if selectedID == item.id {
            selectedID = nil
        }
        reload()
    }

    func clearUnpinned() {
        try? store.clearUnpinnedHistory()
        reload()
    }
}
