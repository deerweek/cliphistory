import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settingsModel: SettingsModel
    var onPaste: (ClipItem) -> Void
    var onSaveSnippet: (String, String) -> Void
    var onClearUnpinned: () -> Void
    var onPageChange: (PanelPage) -> Void

    @Namespace private var categoryNS

    private var panelTheme: PanelThemeContext {
        PanelThemeContext(
            accent: settingsModel.panelAccent.color,
            density: settingsModel.panelDensity,
            opacity: settingsModel.panelOpacity
        )
    }

    private func space(_ value: CGFloat) -> CGFloat {
        panelTheme.spacing(value)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.page != .list {
                navigationBar
                Divider().overlay(Theme.hairline)
            }
            switch model.page {
            case .list:
                listPage
            case .settings:
                SettingsView(model: settingsModel)
            case .composer:
                AddSnippetView(onSave: onSaveSnippet)
            }
        }
        .padding(.top, Self.titlebarInset)
        .frame(minWidth: 460, minHeight: 560)
        .background(.regularMaterial.opacity(panelTheme.opacity))
        .onChange(of: model.page) { _, page in
            onPageChange(page)
        }
        // Propagate the chosen accent to native controls as well as custom
        // pills and selection highlights.
        .tint(panelTheme.accent)
        .environment(\.clipHistoryTheme, panelTheme)
    }

    /// Space reserved at the top for the transparent title bar / traffic lights.
    private static let titlebarInset: CGFloat = 28

    // MARK: - Navigation (settings / composer)

    private var navigationBar: some View {
        HStack(spacing: space(Theme.Space.sm)) {
            Button { model.page = .list } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("返回")

            Spacer()
            Text(model.page.title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 26, height: 26)
        }
        .padding(.horizontal, space(Theme.Space.md))
        .padding(.vertical, space(Theme.Space.sm))
    }

    // MARK: - List page

    private var listPage: some View {
        VStack(spacing: 0) {
            header
            if !model.counts.isEmpty {
                categoryBar
            }
            if !model.accessibilityTrusted {
                accessibilityBanner
            }
            if let attachStatus = model.attachStatus {
                attachBanner(attachStatus)
            }
            Divider().overlay(Theme.hairline)
            if model.items.isEmpty {
                emptyState
            } else {
                itemList
            }
            Divider().overlay(Theme.hairline)
            footer
        }
    }

    private var header: some View {
        VStack(spacing: space(Theme.Space.md)) {
            HStack(alignment: .firstTextBaseline) {
                Text("剪贴板记录")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(model.items.count) 条")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            searchField
        }
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.top, space(Theme.Space.md))
        .padding(.bottom, space(Theme.Space.md))
    }

    private var searchField: some View {
        HStack(spacing: space(Theme.Space.sm)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("搜索复制记录或快捷回复", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    if let item = model.selectedItem {
                        onPaste(item)
                    }
                }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, space(Theme.Space.md))
        .padding(.vertical, space(8))
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.controlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Category filter bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(nil, title: "全部", symbol: "square.grid.2x2",
                             count: model.counts.values.reduce(0, +))
                ForEach(model.availableCategories, id: \.self) { category in
                    categoryChip(category, title: category.title, symbol: category.symbolName,
                                 count: model.counts[category])
                }
            }
            .padding(.horizontal, space(Theme.Space.lg))
            .padding(.bottom, space(Theme.Space.sm))
        }
    }

    private func categoryChip(_ category: ClipCategory?, title: String, symbol: String, count: Int?) -> some View {
        let selected = model.category == category
        return Button {
            withAnimation(.snappy(duration: 0.22)) { model.category = category }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Color.white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if selected {
                    Capsule().fill(panelTheme.accent)
                        .matchedGeometryEffect(id: "categoryPill", in: categoryNS)
                } else {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var accessibilityBanner: some View {
        Banner(
            symbol: "exclamationmark.triangle.fill",
            tint: .orange,
            message: "当前运行的应用副本还没有辅助功能权限。选择条目会先复制；到设置里授权当前路径对应的“剪贴板记录”后即可自动粘贴。",
            actionTitle: "去开启",
            action: { model.page = .settings }
        )
    }

    private func attachBanner(_ text: String) -> some View {
        HStack(spacing: space(Theme.Space.sm)) {
            Image(systemName: "pip")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.bottom, space(Theme.Space.sm))
    }

    private var emptyState: some View {
        VStack(spacing: space(Theme.Space.md)) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.primary.opacity(0.05)))
            VStack(spacing: space(Theme.Space.xs)) {
                Text(model.query.isEmpty ? "还没有记录" : "没有匹配结果")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.query.isEmpty ? "复制文本或图片，也可以添加一条常用的快捷回复。" : "换个关键词或分类试试。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.query.isEmpty {
                Button { model.page = .composer } label: {
                    Label("添加快捷回复", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, space(Theme.Space.xs))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, space(Theme.Space.xl))
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { pair in
                        ItemRow(
                            item: pair.element,
                            index: pair.offset,
                            isSelected: pair.element.id == model.selectedID,
                            onPaste: { onPaste(pair.element) },
                            onSelect: { model.selectedID = pair.element.id },
                            onTogglePin: { model.togglePin(pair.element) },
                            onDelete: { model.delete(pair.element) }
                        )
                        .id(pair.element.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal, space(Theme.Space.sm))
                .padding(.vertical, space(Theme.Space.sm))
                .animation(.easeInOut(duration: 0.18), value: model.items)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: space(Theme.Space.md)) {
            ShortcutHint(keys: "↑↓", label: "选择")
            ShortcutHint(keys: "↵", label: "粘贴")
            ShortcutHint(keys: "⌘1–9", label: "快速")
            Spacer()
            Button { model.page = .composer } label: {
                Label("添加回复", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelTheme.accent)

            Menu {
                Button { model.page = .settings } label: {
                    Label("设置…", systemImage: "gearshape")
                }
                Divider()
                Button(role: .destructive, action: onClearUnpinned) {
                    Label("清空未置顶历史", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
        }
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.vertical, space(Theme.Space.sm))
    }
}

// MARK: - Banner

private struct Banner: View {
    @Environment(\.clipHistoryTheme) private var theme

    let symbol: String
    let tint: Color
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(Theme.Space.sm)) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: theme.spacing(Theme.Space.sm))
            Button(actionTitle, action: action)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(tint)
        }
        .padding(theme.spacing(Theme.Space.md))
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .padding(.horizontal, theme.spacing(Theme.Space.md))
        .padding(.bottom, theme.spacing(Theme.Space.sm))
    }
}

// MARK: - Item row

private struct ItemRow: View {
    @Environment(\.clipHistoryTheme) private var theme

    let item: ClipItem
    let index: Int
    let isSelected: Bool
    var onPaste: () -> Void
    var onSelect: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(Theme.Space.sm)) {
            if index < 9 {
                DigitChip(number: index + 1)
                    .padding(.top, 3)
            }
            leadingArt
            content
            Spacer(minLength: theme.spacing(Theme.Space.sm))
            if hovering || isSelected {
                trailingActions.transition(.opacity)
            }
        }
        .padding(.horizontal, theme.spacing(Theme.Space.md))
        .padding(.vertical, theme.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(isSelected ? theme.accent.opacity(0.45) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.10)) { hovering = hover }
        }
        .onTapGesture {
            onSelect()
            onPaste()
        }
        .contextMenu {
            Button("粘贴", action: onPaste)
            Button(item.isPinned ? "取消置顶" : "置顶", action: onTogglePin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var leadingArt: some View {
        if item.contentType == .image, let data = item.imageData {
            Thumbnail(data: data)
        } else {
            KindGlyph(symbol: glyphSymbol, tint: glyphTint)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if item.isPinned {
                    Badge(text: "置顶", tint: .orange)
                }
                if item.kind == .snippet {
                    Badge(text: "回复")
                } else if item.contentType == .link {
                    Badge(text: "链接", filled: false)
                }
            }
            Text(item.body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(theme.rowBodyLineLimit)
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 2) {
            IconButton(
                symbol: item.isPinned ? "pin.slash" : "pin",
                help: item.isPinned ? "取消置顶" : "置顶",
                action: onTogglePin
            )
            IconButton(symbol: "trash", help: "删除", role: .destructive, action: onDelete)
        }
    }

    private var background: Color {
        if isSelected { return theme.selectedFill }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var glyphSymbol: String {
        switch item.category {
        case .link: return "link"
        case .snippet: return "text.bubble.fill"
        case .image: return "photo"
        case .text: return "doc.on.clipboard.fill"
        }
    }

    private var glyphTint: Color {
        if item.isPinned { return .orange }
        switch item.category {
        case .link, .snippet: return theme.accent
        default: return .secondary
        }
    }
}

private struct DigitChip: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

private struct Thumbnail: View {
    let data: Data

    var body: some View {
        Group {
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}
