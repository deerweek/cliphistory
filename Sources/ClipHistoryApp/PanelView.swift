import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settingsModel: SettingsModel
    var onPaste: (ClipItem) -> Void
    var onSaveSnippet: (String, String) -> Void
    var onClearUnpinned: () -> Void
    var onPageChange: (PanelPage) -> Void

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
        .background(.regularMaterial)
        .onChange(of: model.page) { _, page in
            onPageChange(page)
        }
    }

    /// Space reserved at the top for the transparent title bar / traffic lights.
    private static let titlebarInset: CGFloat = 28

    // MARK: - Navigation (settings / composer)

    private var navigationBar: some View {
        HStack(spacing: Theme.Space.sm) {
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
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    // MARK: - List page

    private var listPage: some View {
        VStack(spacing: 0) {
            header
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
        VStack(spacing: Theme.Space.md) {
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
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.md)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.sm) {
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
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.controlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        )
    }

    private var accessibilityBanner: some View {
        Banner(
            symbol: "exclamationmark.triangle.fill",
            tint: .orange,
            message: "辅助功能还没生效。选择条目会先复制，需要你再按 ⌘V。到设置里关掉再打开一次开关，然后重新启动。",
            actionTitle: "去开启",
            action: { model.page = .settings }
        )
    }

    private func attachBanner(_ text: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "pip")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(
                    Circle().fill(Color.primary.opacity(0.05))
                )
            VStack(spacing: Theme.Space.xs) {
                Text(model.query.isEmpty ? "还没有记录" : "没有匹配结果")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.query.isEmpty ? "复制任意文本，或添加一条常用的快捷回复。" : "换个关键词试试。")
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
                .padding(.top, Theme.Space.xs)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.xl)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.items) { item in
                        ItemRow(
                            item: item,
                            isSelected: item.id == model.selectedID,
                            onPaste: { onPaste(item) },
                            onSelect: { model.selectedID = item.id },
                            onTogglePin: { model.togglePin(item) },
                            onDelete: { model.delete(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.sm)
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
        HStack(spacing: Theme.Space.md) {
            ShortcutHint(keys: "↑↓", label: "选择")
            ShortcutHint(keys: "↵", label: "粘贴")
            ShortcutHint(keys: "⌥⌫", label: "删除")
            Spacer()
            Button { model.page = .composer } label: {
                Label("添加回复", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

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
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
    }
}

// MARK: - Banner

private struct Banner: View {
    let symbol: String
    let tint: Color
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.sm)
            Button(actionTitle, action: action)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(tint)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, Theme.Space.sm)
    }
}

// MARK: - Item row

private struct ItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    var onPaste: () -> Void
    var onSelect: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            KindGlyph(symbol: glyphSymbol, tint: glyphTint)

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
                    }
                }
                Text(item.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Space.sm)

            if hovering || isSelected {
                HStack(spacing: 2) {
                    IconButton(
                        symbol: item.isPinned ? "pin.slash" : "pin",
                        help: item.isPinned ? "取消置顶" : "置顶",
                        action: onTogglePin
                    )
                    IconButton(symbol: "trash", help: "删除", role: .destructive, action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
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

    private var background: Color {
        if isSelected { return Theme.rowSelected }
        if hovering { return Theme.rowHover }
        return .clear
    }

    private var glyphSymbol: String {
        item.kind == .snippet ? "text.bubble.fill" : "doc.on.clipboard.fill"
    }

    private var glyphTint: Color {
        if item.isPinned { return .orange }
        return item.kind == .snippet ? .accentColor : .secondary
    }
}
