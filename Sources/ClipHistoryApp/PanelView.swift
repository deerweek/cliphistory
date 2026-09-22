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
                Divider()
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
        .frame(minWidth: 440, minHeight: 520)
        .background(.regularMaterial)
        .onChange(of: model.page) { _, page in
            onPageChange(page)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button(action: { model.page = .list }) {
                Label("返回", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text(model.page.title)
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var listPage: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.accessibilityTrusted {
                accessibilityBanner
                Divider()
            }
            if let attachStatus = model.attachStatus {
                Text(attachStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                Divider()
            }
            if model.items.isEmpty {
                emptyState
            } else {
                itemList
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索复制记录或快捷回复", text: $model.query)
                .textFieldStyle(.plain)
                .onSubmit {
                    if let item = model.selectedItem {
                        onPaste(item)
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("辅助功能还没生效。选择条目会先复制，需要你再按 ⌘V。到设置里关掉再打开一次开关，然后重新启动。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("去开启") {
                model.page = .settings
            }
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("还没有记录")
                .font(.headline)
            Text("复制文本，或添加一条快捷回复。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("添加快捷回复") {
                model.page = .composer
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var itemList: some View {
        List(selection: $model.selectedID) {
            ForEach(model.items) { item in
                ItemRow(
                    item: item,
                    onPaste: { onPaste(item) },
                    onTogglePin: { model.togglePin(item) },
                    onDelete: { model.delete(item) }
                )
                .tag(item.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("添加回复") { model.page = .composer }
            Button("清空未置顶", action: onClearUnpinned)
            Spacer()
            Button("设置") { model.page = .settings }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ItemRow: View {
    let item: ClipItem
    var onPaste: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if item.kind == .snippet {
                        Text("回复")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if item.isPinned {
                        Text("置顶")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                }
                .help(item.isPinned ? "取消置顶" : "置顶")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("删除")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .contextMenu {
            Button("粘贴", action: onPaste)
            Button(item.isPinned ? "取消置顶" : "置顶", action: onTogglePin)
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var iconName: String {
        if item.isPinned { return "pin.fill" }
        return item.kind == .snippet ? "text.bubble" : "doc.on.clipboard"
    }
}
