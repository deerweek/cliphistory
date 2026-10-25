import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settingsModel: SettingsModel
    var onPaste: (ClipItem) -> Void
    var onPasteRawText: (String, Int64?) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onCopyRawText: (String) -> Void
    var onTranslateItem: (ClipItem, Bool) -> Void
    var onRunAction: (ClipActionDescriptor, ClipItem) -> Void
    var onRecognizeImageText: (ClipItem) -> Void = { _ in }
    var onExportImage: (ClipItem) -> Void = { _ in }
    var onSaveItem: (Int64?, String, String, ItemKind, String?, SmartArchiveTag) -> Void
    var onClearUnpinned: () -> Void
    var onClose: () -> Void = {}
    var onPageChange: (PanelPage) -> Void

    @Namespace private var categoryNS
    @FocusState private var isSearchFocused: Bool

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

    private var isSplitView: Bool {
        settingsModel.showPreviewPane
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if model.page != .list {
                    navigationBar
                    Divider().overlay(Theme.hairline)
                }
                switch model.page {
                case .list:
                    listPage
                case .settings:
                    SettingsView(
                        model: settingsModel,
                        store: model.store,
                        onToast: { msg in model.showToast(msg) },
                        onReload: { model.reload() }
                    )
                case .composer:
                    AddSnippetView(
                        editingItem: model.editingItem,
                        onSave: onSaveItem,
                        onCancel: { model.page = .list }
                    )
                case .actions:
                    ActionStudioView(
                        settingsModel: settingsModel,
                        onToast: { msg in model.showToast(msg, symbol: "wand.and.stars") }
                    )
                }
            }
            .padding(.top, Self.titlebarInset)

            if let toast = model.toastMessage {
                ToastCapsule(
                    symbol: model.toastSymbol,
                    message: toast,
                    tint: panelTheme.accent
                )
                .padding(.bottom, 46)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.25), value: model.toastMessage)
        .frame(
            minWidth: isSplitView ? 720 : 470,
            idealWidth: isSplitView ? 800 : 520,
            minHeight: 520
        )
        .background(.ultraThinMaterial)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.38))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.primary.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        )
        .onChange(of: model.page) { _, page in
            onPageChange(page)
            if page == .list {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: model.searchFocusTrigger) { _, _ in
            if model.page == .list {
                isSearchFocused = true
            }
        }
        .onAppear {
            if model.page == .list {
                isSearchFocused = true
            }
        }
        .tint(panelTheme.accent)
        .environment(\.clipHistoryTheme, panelTheme)
    }

    private static let titlebarInset: CGFloat = 6

    // MARK: - Navigation (settings / composer / actions)

    private var navigationBar: some View {
        HStack(spacing: space(Theme.Space.sm)) {
            Button { model.page = .list } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("返回列表 (Esc)")

            Spacer()
            Text(navigationTitle)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                IconButton(
                    symbol: "xmark",
                    help: "关闭面板 (⌘W)",
                    action: onClose
                )
            }
            .frame(width: 52, height: 26)
        }
        .padding(.horizontal, space(Theme.Space.md))
        .padding(.vertical, space(Theme.Space.sm))
    }

    private var navigationTitle: String {
        switch model.page {
        case .composer:
            return model.editingItem == nil ? "新建快捷回复" : "编辑条目与短码"
        default:
            return model.page.title
        }
    }

    // MARK: - List page

    private var listPage: some View {
        VStack(spacing: 0) {
            header
            if model.hasAnyStoredItems || model.category != nil || model.smartTagFilter != nil || !model.query.isEmpty {
                unifiedFilterBar
            }
            if model.isRecordingPaused {
                pausedRecordingBanner
            }
            if let recommended = model.recommendedReply, settingsModel.enableSmartReply {
                smartReplyBanner(recommended)
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
            } else if settingsModel.showPreviewPane {
                HStack(spacing: 0) {
                    itemList
                        .frame(minWidth: 325, idealWidth: 355, maxWidth: 395)
                    Divider().overlay(Theme.hairline)
                    InspectorPane(
                        item: model.selectedItem,
                        searchQuery: model.query,
                        pasteTarget: model.pasteTargetInfo,
                        accessibilityTrusted: model.accessibilityTrusted,
                        translatedText: model.translatedForItemID == model.selectedItem?.id ? model.translatedText : nil,
                        isRunningAction: model.isRunningAction,
                        enabledActions: settingsModel.enabledActions,
                        suggestedActionID: model.suggestedActionID,
                        onPaste: { item in onPaste(item) },
                        onPasteRawText: { text, id in onPasteRawText(text, id) },
                        onCopyOnly: { item in onCopyOnly(item) },
                        onCopyRawText: { text in onCopyRawText(text) },
                        onSaveTransformed: { text in model.saveTransformedAsHistory(text) },
                        onClearTranslated: { model.clearTranslatedResult() },
                        onTranslate: { item, pasteImmediately in onTranslateItem(item, pasteImmediately) },
                        onRunAction: { action, item in onRunAction(action, item) },
                        onRecognizeImageText: { item in onRecognizeImageText(item) },
                        onExportImage: { item in onExportImage(item) },
                        onOpenActionStudio: { model.page = .actions },
                        onEdit: { item in model.openEdit(item) },
                        onTogglePin: { item in model.togglePin(item) },
                        onConvertSnippet: { item in model.convertToSnippet(item) },
                        onDelete: { item in model.delete(item) }
                    )
                    .frame(minWidth: 375, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                itemList
            }

            Divider().overlay(Theme.hairline)
            footer
        }
    }

    // MARK: - Spotlight-Style Integrated Command Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            searchField

            HStack(spacing: 2) {
                IconButton(
                    symbol: model.isRecordingPaused ? "pause.circle.fill" : "pause.circle",
                    help: model.isRecordingPaused ? "已暂停记录剪贴板（点击恢复记录）" : "暂停记录剪贴板（复制密码或敏感内容时使用）",
                    isActive: model.isRecordingPaused,
                    activeTint: .orange
                ) {
                    model.toggleRecordingPaused()
                }

                IconButton(
                    symbol: "wand.and.stars",
                    help: "动作工坊：自由添加翻译、AI 指令或脚本插件"
                ) {
                    model.page = .actions
                }

                IconButton(
                    symbol: "plus.bubble",
                    help: "新建快捷回复与输入法触发码 (⌘N)"
                ) {
                    model.openNewSnippet()
                }

                IconButton(
                    symbol: "sidebar.trailing",
                    help: settingsModel.showPreviewPane ? "收起右侧预览栏 (⌘Y)" : "展开右侧预览栏 (⌘Y)",
                    isActive: settingsModel.showPreviewPane,
                    activeTint: panelTheme.accent
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        settingsModel.showPreviewPane.toggle()
                    }
                }

                IconButton(
                    symbol: "gearshape",
                    help: "设置与 Jev 模型配置 (⌘,)"
                ) {
                    model.page = .settings
                }

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)

                IconButton(
                    symbol: "xmark",
                    help: "收起面板 (Esc / ⌘W)",
                    action: onClose
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.038))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.specularStroke, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, space(Theme.Space.md))
        .padding(.top, space(6))
        .padding(.bottom, space(6))
    }

    @ViewBuilder
    private var pasteDestinationPill: some View {
        if let target = model.pasteTargetInfo, model.accessibilityTrusted {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(panelTheme.accent)
                if let icon = target.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                }
                Text(target.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("· \(model.items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(panelTheme.accent.opacity(0.11)))
            .overlay(Capsule().strokeBorder(panelTheme.accent.opacity(0.22), lineWidth: 0.5))
            .help("按下 ↵ 或双击条目时，内容将自动粘贴到 \(target.name)（当前列表共 \(model.items.count) 条）")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("剪贴板 · \(model.items.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.055)))
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isSearchFocused ? panelTheme.accent : .secondary)

            TextField("搜索剪贴板、标题备注，或输入 ;短码 直达…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    if let item = model.selectedItem {
                        onPaste(item)
                    }
                }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索 (Esc)")
            }

            pasteDestinationPill
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.controlFill)
                .shadow(color: isSearchFocused ? panelTheme.accent.opacity(0.10) : .black.opacity(0.03), radius: 5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSearchFocused
                        ? LinearGradient(colors: [panelTheme.accent.opacity(0.60), panelTheme.accent.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                        : Theme.specularStroke,
                    lineWidth: isSearchFocused ? 1.0 : 0.75
                )
        )
    }

    // MARK: - Unified Single-Row Category & Smart Archive Filter Bar

    private var unifiedFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    categoryChip(nil, title: "全部", symbol: "square.grid.2x2",
                                 count: model.totalMatchingCount)
                    ForEach(model.availableCategories, id: \.self) { category in
                        categoryChip(category, title: category.title, symbol: category.symbolName,
                                     count: model.counts[category])
                    }
                }
                .padding(2.5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.042))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )

                if !model.availableSmartTags.isEmpty || model.smartTagFilter != nil {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)

                    ForEach(model.availableSmartTags, id: \.self) { tag in
                        let active = model.smartTagFilter == tag
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                model.smartTagFilter = active ? nil : tag
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: tag.symbolName)
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(tag.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                if let count = model.smartTagCounts[tag] {
                                    Text("\(count)")
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .opacity(0.75)
                                }
                            }
                            .foregroundStyle(active ? panelTheme.accent : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(active ? panelTheme.accent.opacity(0.14) : Color.primary.opacity(0.038))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(active ? panelTheme.accent.opacity(0.42) : Color.primary.opacity(0.07), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, space(Theme.Space.md))
            .padding(.bottom, space(6))
        }
    }

    private func categoryChip(_ category: ClipCategory?, title: String, symbol: String, count: Int?) -> some View {
        let selected = model.category == category
        let resolvedCount = count ?? 0
        return Button {
            withAnimation(.snappy(duration: 0.22)) { model.category = category }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                if resolvedCount > 0 || selected {
                    Text("\(resolvedCount)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(selected ? 0.90 : 0.62)
                }
            }
            .foregroundStyle(selected ? Color.white : (resolvedCount > 0 ? Color.secondary : Color.secondary.opacity(0.50)))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if selected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [panelTheme.accent, panelTheme.accent.opacity(0.86)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: panelTheme.accent.opacity(0.28), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "categoryPill", in: categoryNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ⚡ Jev Smart Reply Recommendation Banner

    private func smartReplyBanner(_ snippet: ClipItem) -> some View {
        let pct = Int((model.replyConfidence * 100).rounded())
        return HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(panelTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("推荐回复：\(snippet.displayTitle)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Badge(
                        text: model.isJevRecommended ? "Jev \(pct)% 把握" : "智能匹配 \(pct)%",
                        symbol: "sparkles",
                        tint: panelTheme.accent
                    )
                }
                Text(snippet.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onPaste(snippet)
            } label: {
                HStack(spacing: 4) {
                    Text("粘贴回复")
                        .font(.system(size: 11, weight: .semibold))
                    Text("⌘R")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(panelTheme.accent))
            }
            .buttonStyle(.plain)

            Button {
                model.dismissRecommendedReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(panelTheme.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(panelTheme.accent.opacity(0.30), lineWidth: 1)
                )
        )
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.bottom, space(Theme.Space.sm))
    }

    private var pausedRecordingBanner: some View {
        Banner(
            symbol: "pause.circle.fill",
            tint: .orange,
            message: "已暂停记录剪贴板：当前新复制的密码或敏感文本不会被保存。",
            actionTitle: "恢复记录",
            action: { model.setRecordingPaused(false) }
        )
    }

    private var accessibilityBanner: some View {
        Banner(
            symbol: "exclamationmark.triangle.fill",
            tint: .orange,
            message: "当前应用副本尚未开启辅助功能权限。点击条目会写回剪贴板；授权后可开启自动粘贴与输入法短码展开。",
            actionTitle: "去开启",
            action: { model.page = .settings }
        )
    }

    private func attachBanner(_ text: String) -> some View {
        HStack(spacing: space(Theme.Space.sm)) {
            Image(systemName: "pip")
                .font(.system(size: 11))
                .foregroundStyle(panelTheme.accent)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.bottom, space(Theme.Space.sm))
    }

    private var emptyState: some View {
        let isSnippetTabEmpty = model.category == .snippet && model.query.isEmpty && model.smartTagFilter == nil
        let isFiltered = !model.query.isEmpty || model.category != nil || model.smartTagFilter != nil

        let iconName: String = {
            if isSnippetTabEmpty { return "text.bubble" }
            if isFiltered { return "magnifyingglass" }
            return "doc.on.clipboard"
        }()

        let titleText: String = {
            if isSnippetTabEmpty { return "还没有快捷回复" }
            if isFiltered { return "没有找到匹配内容" }
            return "还没有剪贴板记录"
        }()

        let subtitleText: String = {
            if isSnippetTabEmpty {
                return "把常用地址、发票抬头、客服话术或代码片段保存为快捷回复，支持绑定 ;短码 随时打字自动展开。"
            }
            if isFiltered {
                return "当前搜索词或分类下暂无记录，试试调整关键词或按 Esc 清空筛选条件。"
            }
            return "在任意应用中按 ⌘C 复制文本、代码、链接或图片，都会自动分类归档到这里。"
        }()

        return VStack(spacing: space(Theme.Space.md)) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(panelTheme.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(panelTheme.accent.opacity(0.10)))
            VStack(spacing: space(Theme.Space.xs)) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            HStack(spacing: 8) {
                if isSnippetTabEmpty || !isFiltered {
                    Button { model.openNewSnippet() } label: {
                        Label("新建快捷回复", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                if isFiltered {
                    Button("重置筛选条件 (Esc)") {
                        model.query = ""
                        model.category = nil
                        model.smartTagFilter = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.top, space(Theme.Space.xs))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, space(Theme.Space.xl))
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { pair in
                        ItemRow(
                            item: pair.element,
                            index: pair.offset,
                            searchQuery: model.query,
                            isSelected: pair.element.id == model.selectedID,
                            singleClickPastes: !settingsModel.showPreviewPane,
                            onPaste: { onPaste(pair.element) },
                            onCopyOnly: { onCopyOnly(pair.element) },
                            onTranslatePaste: { onTranslateItem(pair.element, true) },
                            onSelect: { model.selectedID = pair.element.id },
                            onEdit: { model.openEdit(pair.element) },
                            onTogglePin: { model.togglePin(pair.element) },
                            onConvertSnippet: { model.convertToSnippet(pair.element) },
                            onDelete: { model.delete(pair.element) }
                        )
                        .id(pair.element.id)
                    }
                }
                .padding(.horizontal, space(Theme.Space.sm))
                .padding(.vertical, space(Theme.Space.sm))
            }
            .onChange(of: model.scrollTrigger) { _, _ in
                guard let id = model.selectedID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: space(Theme.Space.md)) {
            ShortcutHint(keys: "↑↓", label: "选择")
            ShortcutHint(keys: "↵", label: "粘贴")
            ShortcutHint(keys: "⇧↵", label: "连贴下移")
            ShortcutHint(keys: "⌘T", label: "即译即贴")
            ShortcutHint(keys: "⌘C", label: "仅复制")
            ShortcutHint(keys: "⌘E", label: "编辑/短码")
            Spacer()
            Button { model.page = .actions } label: {
                Label("动作工坊", systemImage: "wand.and.stars")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button { model.openNewSnippet() } label: {
                Label("添加快捷回复", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelTheme.accent)

            Menu {
                Button { model.openNewSnippet() } label: {
                    Label("新建快捷回复与短码 (⌘N)", systemImage: "plus.bubble")
                }
                Button { model.page = .actions } label: {
                    Label("动作工坊：自由添加插件…", systemImage: "wand.and.stars")
                }
                Button { settingsModel.showPreviewPane.toggle() } label: {
                    Label(settingsModel.showPreviewPane ? "收起右侧预览栏 (⌘Y)" : "展开右侧预览栏 (⌘Y)",
                          systemImage: "sidebar.trailing")
                }
                Button { model.page = .settings } label: {
                    Label("设置与 Jev 模型… (⌘,)", systemImage: "gearshape")
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
            .help("更多操作")
        }
        .padding(.horizontal, space(Theme.Space.lg))
        .padding(.vertical, space(Theme.Space.sm))
    }
}

// MARK: - Live Inspector & Pluggable Action Hub

private struct InspectorPane: View {
    @Environment(\.clipHistoryTheme) private var theme

    let item: ClipItem?
    let searchQuery: String
    let pasteTarget: PasteTargetInfo?
    let accessibilityTrusted: Bool
    let translatedText: String?
    let isRunningAction: Bool
    let enabledActions: [ClipActionDescriptor]
    let suggestedActionID: String?
    var onPaste: (ClipItem) -> Void
    var onPasteRawText: (String, Int64?) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onCopyRawText: (String) -> Void
    var onSaveTransformed: (String) -> Void
    var onClearTranslated: () -> Void
    var onTranslate: (ClipItem, Bool) -> Void
    var onRunAction: (ClipActionDescriptor, ClipItem) -> Void
    var onRecognizeImageText: (ClipItem) -> Void
    var onExportImage: (ClipItem) -> Void
    var onOpenActionStudio: () -> Void
    var onEdit: (ClipItem) -> Void
    var onTogglePin: (ClipItem) -> Void
    var onConvertSnippet: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                inspectorHeader(item)
                Divider().overlay(Theme.hairline)
                inspectorContent(item)
                Divider().overlay(Theme.hairline)
                inspectorUnifiedDock(item)
            }
            .background(Color.primary.opacity(0.012))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("选择一条记录查看详情或执行转换")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inspectorHeader(_ item: ClipItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if item.isPinned {
                        Badge(text: "置顶", symbol: "pin.fill", tint: .orange)
                    }
                    if item.kind == .snippet {
                        Badge(text: "快捷回复", symbol: "text.bubble.fill")
                    }
                    if let code = item.triggerCode, !code.isEmpty {
                        Badge(text: "短码 \(code)", symbol: "keyboard", tint: .purple)
                    }
                    if item.smartTag != .general {
                        Badge(text: item.smartTag.title, symbol: item.smartTag.symbolName, tint: .cyan)
                    } else if item.contentType == .link {
                        Badge(text: "链接", symbol: "link")
                    } else if item.contentType == .image {
                        Badge(text: "图片", symbol: "photo")
                    }
                    if item.hasCustomTitle {
                        Text(item.title ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 5) {
                    if let appIcon = ThumbnailCache.shared.appIcon(forSourceApp: item.sourceApp) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 13, height: 13)
                    }
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                            .fontWeight(.medium)
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.relativeTime())
                    Text("· \(item.metadataSummary)")
                        .monospacedDigit()
                    if item.useCount > 0 {
                        Text("· 复用 \(item.useCount) 次")
                            .fontWeight(.medium)
                            .foregroundStyle(theme.accent)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                onEdit(item)
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.hasTriggerCode ? "改短码 / 编辑" : "设短码 / 编辑")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(theme.accent.opacity(0.11))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(theme.accent.opacity(0.24), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("编辑标题、正文或绑定输入法触发短码 (⌘E)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func inspectorContent(_ item: ClipItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                if item.contentType == .image, let data = item.imageData {
                    imagePreviewCard(item: item, data: data)
                    if let ocrOrTranslated = translatedText ?? item.imageOCRText {
                        translationResultCard(
                            item: item,
                            translated: ocrOrTranslated,
                            badgeTitle: "图中识别文字 (OCR)"
                        )
                    }
                } else {
                    if let code = item.extractedCredentialCode {
                        credentialPreviewCard(item: item, code: code)
                    }
                    if let hex = item.hexColor {
                        colorPreviewCard(hex: hex)
                    }
                    if item.contentType == .link {
                        linkPreviewCard(item: item)
                    }
                    if item.isForeignLanguage && translatedText == nil {
                        foreignLanguagePromptBanner(item: item)
                    }
                    if let translatedText {
                        translationResultCard(item: item, translated: translatedText, badgeTitle: "转换结果")
                    }
                    textPreviewCard(item: item)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func credentialPreviewCard(item: ClipItem, code: String) -> some View {
        HStack(spacing: 10) {
            KindGlyph(symbol: "key.radiowaves.forward.fill", tint: .pink, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("智能提取验证码 / 单号")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                onCopyRawText(code)
            } label: {
                Label("仅复制号码", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onPasteRawText(code, item.id)
            } label: {
                Label("仅粘贴 \(code)", systemImage: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.11), Color.pink.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(Color.pink.opacity(0.28), lineWidth: 0.75)
                )
        )
    }

    private func foreignLanguagePromptBanner(item: ClipItem) -> some View {
        HStack(spacing: 10) {
            KindGlyph(symbol: "character.bubble.fill", tint: theme.accent, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到外文内容")
                    .font(.system(size: 12, weight: .semibold))
                Text("支持一键翻译为中文并直接粘贴至目标窗口")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onTranslate(item, false)
            } label: {
                Text("预览译文")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onTranslate(item, true)
            } label: {
                Label("译为中文并粘贴 (⌘T)", systemImage: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.11), theme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.25), lineWidth: 0.75)
                )
        )
    }

    private func translationResultCard(item: ClipItem, translated: String, badgeTitle: String = "转换结果") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Badge(text: badgeTitle, symbol: "sparkles", tint: theme.accent)
                Spacer()
                Button {
                    onSaveTransformed(translated)
                } label: {
                    Label("存为记录", systemImage: "plus.circle")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("将此结果保存为一条新的纯文本剪贴板记录")

                Button {
                    onCopyRawText(translated)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    onPasteRawText(translated, item.id)
                } label: {
                    Label("粘贴文字", systemImage: "arrow.turn.down.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if self.translatedText != nil {
                    Button(action: onClearTranslated) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("关闭转换结果卡片")
                }
            }

            Text(translated)
                .font(.system(size: 12.5, design: ContentClassifier.isCodeLike(translated) ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineSpacing(3.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.11), theme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.30), lineWidth: 0.75)
                )
        )
    }

    private func imagePreviewCard(item: ClipItem, data: Data) -> some View {
        VStack(spacing: 10) {
            if let nsImage = ThumbnailCache.shared.previewImage(for: item.id, data: data) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .fill(Color.black.opacity(0.04))

                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
                )
            }
            HStack(spacing: 12) {
                Label(item.imageDimensionsLabel, systemImage: "aspectratio")
                Label(ClipItem.formatByteCount(data.count), systemImage: "internaldrive")
                Spacer()
                Button {
                    onRecognizeImageText(item)
                } label: {
                    Label(item.imageOCRText == nil ? "OCR 识字" : "重新识字", systemImage: "text.viewfinder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)

                Button {
                    onExportImage(item)
                } label: {
                    Label("导出 PNG", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func colorPreviewCard(hex: (r: Double, g: Double, b: Double, hex: String)) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(red: hex.r, green: hex.g, blue: hex.b))
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color(red: hex.r, green: hex.g, blue: hex.b).opacity(0.32), radius: 5, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(hex.hex)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("RGB(\(Int((hex.r * 255).rounded())), \(Int((hex.g * 255).rounded())), \(Int((hex.b * 255).rounded())))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Theme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
                )
        )
    }

    private func linkPreviewCard(item: ClipItem) -> some View {
        let targetURL = item.extractedURL ?? item.body
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                KindGlyph(symbol: "globe", tint: theme.accent, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.linkHost ?? "网页链接")
                        .font(.system(size: 12, weight: .semibold))
                    Text(item.hasEmbeddedURLWithExtraText ? targetURL : "可直接在默认浏览器中打开访问")
                        .font(.system(size: 10.5, design: item.hasEmbeddedURLWithExtraText ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if item.hasEmbeddedURLWithExtraText {
                    Button {
                        onCopyRawText(targetURL)
                    } label: {
                        Text("仅复制链接")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("去除前后文字，仅复制纯链接地址")

                    Button {
                        onPasteRawText(targetURL, item.id)
                    } label: {
                        Text("仅粘贴链接")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("去除前后文字，仅粘贴纯链接地址")
                }
                Button {
                    openURLString(targetURL)
                } label: {
                    Label("打开链接", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Theme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
                )
        )
    }

    private func textPreviewCard(item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: item.isCode ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(item.isCode ? "代码片段 · Monospaced" : "正文内容")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    onCopyOnly(item)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9.5))
                        Text("复制全文")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.024))

            Divider().overlay(Theme.hairline.opacity(0.6))

            Text(TextHighlight.attributed(item.body, query: searchQuery, accent: theme.accent))
                .font(.system(size: item.isCode ? 12 : 13, design: item.isCode ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(item.isCode ? Color(nsColor: .textBackgroundColor).opacity(0.68) : Theme.cardSurface)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
        )
    }

    // MARK: - Unified Bottom Action Dock (Combines Primary Paste, Action Plugins & Item Tools)

    private func inspectorUnifiedDock(_ item: ClipItem) -> some View {
        VStack(spacing: 7) {
            // Top micro-row inside dock: Pluggable action capsules (only when text or image actions exist)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if isRunningAction {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }

                    if item.contentType == .image {
                        Button {
                            onRecognizeImageText(item)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(item.imageOCRText == nil ? "识别图中文字 (OCR)" : "重新识别并复制文字")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(theme.accent.opacity(0.13)))
                            .overlay(Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onExportImage(item)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("导出 PNG…")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(enabledActions) { action in
                            let isSuggested = suggestedActionID == action.id
                            Button {
                                onRunAction(action, item)
                            } label: {
                                HStack(spacing: 3.5) {
                                    Image(systemName: action.symbolName)
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text(action.title)
                                        .font(.system(size: 10.5, weight: isSuggested ? .semibold : .medium))
                                    if action.id == "translate_auto" {
                                        Text("⌘T")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .opacity(0.75)
                                    }
                                }
                                .foregroundStyle(isSuggested ? theme.accent : .secondary)
                                .padding(.horizontal, 8.5)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule()
                                        .fill(isSuggested ? theme.accent.opacity(0.14) : Color.primary.opacity(0.048))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSuggested ? theme.accent.opacity(0.40) : Color.primary.opacity(0.07), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(action.pasteAfterRun ? "执行“\(action.title)”并直接粘贴" : "执行“\(action.title)”并在预览区显示结果")
                        }

                        Button(action: onOpenActionStudio) {
                            HStack(spacing: 2.5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("扩展")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 7.5)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 0.75, dash: [3, 2]))
                                    .foregroundStyle(Color.primary.opacity(0.18))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("打开动作工坊，自由添加新的 AI 转换或脚本插件")
                    }
                }
            }

            // Bottom row inside dock: Primary Paste CTA + Copy + Quick Item Controls
            HStack(spacing: 6) {
                Button {
                    onPaste(item)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(pasteButtonLabel)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("将内容粘贴到目标窗口 (↵)")

                Button {
                    onCopyOnly(item)
                } label: {
                    Label("仅复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("仅写回系统剪贴板，不自动发送 ⌘V (⌘C / ⌥↵)")

                if item.contentType == .text {
                    Button {
                        onTranslate(item, false)
                    } label: {
                        Label(item.isChineseText ? "译英" : "译中", systemImage: "character.bubble")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("在预览区显示中英互译对照结果（按 ⌘T 可直接翻译并粘贴）")
                }

                Spacer()

                HStack(spacing: 2) {
                    if item.contentType != .image {
                        IconButton(
                            symbol: item.kind == .snippet ? "clock.arrow.circlepath" : "text.bubble",
                            help: item.kind == .snippet ? "转为普通历史 (⌥S)" : "保存为快捷回复 (⌥S)",
                            isActive: item.kind == .snippet,
                            activeTint: theme.accent
                        ) {
                            onConvertSnippet(item)
                        }
                    }

                    IconButton(
                        symbol: item.isPinned ? "pin.slash.fill" : "pin",
                        help: item.isPinned ? "取消置顶 (⌥P)" : "置顶 (⌥P)",
                        isActive: item.isPinned,
                        activeTint: .orange
                    ) {
                        onTogglePin(item)
                    }

                    IconButton(
                        symbol: "trash",
                        help: "删除此条目 (⌥⌫)",
                        role: .destructive
                    ) {
                        onDelete(item)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.018))
    }

    private var pasteButtonLabel: String {
        if accessibilityTrusted, let target = pasteTarget {
            return "粘贴到 \(target.name)"
        }
        return "粘贴"
    }

    private func openURLString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString: String
        if trimmed.lowercased().hasPrefix("http://") ||
           trimmed.lowercased().hasPrefix("https://") ||
           trimmed.lowercased().hasPrefix("mailto:") ||
           trimmed.lowercased().hasPrefix("ftp://") {
            urlString = trimmed
        } else {
            urlString = "https://" + trimmed
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
                .font(.system(size: 11, weight: .semibold))
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
    var searchQuery: String = ""
    let isSelected: Bool
    let singleClickPastes: Bool
    var onPaste: () -> Void
    var onCopyOnly: () -> Void
    var onTranslatePaste: () -> Void
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onTogglePin: () -> Void
    var onConvertSnippet: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false
    @State private var lastClickTime: TimeInterval = 0

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(10)) {
            leadingArt
                .padding(.top, 1)
            content
            Spacer(minLength: 4)
            if index < 9 && !hovering {
                DigitChip(number: index + 1, isHighlighted: isSelected)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, theme.spacing(Theme.Space.md) + (isSelected ? 2 : 0))
        .padding(.trailing, theme.spacing(Theme.Space.md))
        .padding(.vertical, theme.rowVerticalPadding)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(theme.selectedGradient)
            } else if hovering {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.rowHover)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3, height: 22)
                    .shadow(color: theme.accent.opacity(0.45), radius: 3, x: 1, y: 0)
                    .padding(.leading, 3.5)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LinearGradient(colors: [theme.accent.opacity(0.45), theme.accent.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                        : (hovering ? Theme.specularStroke : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)),
                    lineWidth: isSelected ? 0.85 : 0.65
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleRowTap()
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                trailingActions
                    .padding(.top, max(4, theme.rowVerticalPadding - 2))
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            }
        }
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.12)) { hovering = hover }
        }
        .contextMenu {
            Button("粘贴到目标窗口 (↵)", action: onPaste)
            if item.contentType == .text {
                Button(item.isChineseText ? "翻译为英文并粘贴 (⌘T)" : "翻译为中文并粘贴 (⌘T)", action: onTranslatePaste)
            }
            Button("仅复制到剪贴板 (⌘C)", action: onCopyOnly)
            Divider()
            Button("编辑标题 / 内容 / 绑定输入法短码… (⌘E)", action: onEdit)
            if item.contentType != .image {
                Button(item.kind == .snippet ? "转为普通历史 (⌥S)" : "保存为快捷回复 (⌥S)", action: onConvertSnippet)
            }
            Button(item.isPinned ? "取消置顶 (⌥P)" : "置顶 (⌥P)", action: onTogglePin)
            Divider()
            Button("删除 (⌥⌫)", role: .destructive, action: onDelete)
        }
    }

    private func handleRowTap() {
        let now = ProcessInfo.processInfo.systemUptime
        onSelect()
        if singleClickPastes {
            onPaste()
            return
        }
        if now - lastClickTime <= NSEvent.doubleClickInterval {
            lastClickTime = 0
            onPaste()
        } else {
            lastClickTime = now
        }
    }

    @ViewBuilder
    private var leadingArt: some View {
        if item.contentType == .image, let data = item.imageData {
            Thumbnail(id: item.id, data: data, sourceApp: item.sourceApp)
        } else if let hex = item.hexColor {
            ColorSwatchTile(r: hex.r, g: hex.g, b: hex.b, size: 34, sourceApp: item.sourceApp)
        } else {
            KindGlyph(symbol: glyphSymbol, tint: glyphTint, size: 34, sourceApp: item.sourceApp)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(TextHighlight.attributed(item.displayTitle, query: searchQuery, accent: theme.accent))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: item.isCode && !item.hasCustomTitle ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let code = item.triggerCode, !code.isEmpty {
                    Badge(text: code, symbol: "keyboard", tint: .purple)
                }
                if item.isPinned {
                    Badge(text: "置顶", tint: .orange)
                } else if item.kind == .snippet {
                    Badge(text: "回复")
                } else if item.smartTag != .general {
                    Badge(text: item.smartTag.title, filled: false)
                }
            }

            let secondary = item.secondaryPreviewText
            if !secondary.isEmpty {
                Text(TextHighlight.attributed(secondary, query: searchQuery, accent: theme.accent))
                    .font(.system(size: 11.5, design: item.isCode ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(theme.rowBodyLineLimit)
            }

            HStack(spacing: 4) {
                Text(item.relativeTime())
                if let app = item.sourceApp, !app.isEmpty {
                    Text("· \(app)")
                }
                Text("· \(item.metadataSummary)")
                    .monospacedDigit()
                if item.useCount > 0 {
                    HStack(spacing: 2) {
                        Text("·")
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(item.useCount)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(theme.accent.opacity(0.9))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 2) {
            if !singleClickPastes {
                IconButton(symbol: "arrow.turn.down.left", help: "立即粘贴 (↵)", size: 24, action: onPaste)
            }
            if item.contentType == .text {
                IconButton(symbol: "character.bubble", help: "中英互译并粘贴 (⌘T)", size: 24, action: onTranslatePaste)
            }
            IconButton(symbol: "doc.on.doc", help: "仅复制到剪贴板 (⌘C)", size: 24, action: onCopyOnly)
            IconButton(symbol: "pencil", help: "编辑或设输入法短码 (⌘E)", size: 24, action: onEdit)
            IconButton(
                symbol: item.isPinned ? "pin.slash.fill" : "pin",
                help: item.isPinned ? "取消置顶 (⌥P)" : "置顶 (⌥P)",
                isActive: item.isPinned,
                activeTint: .orange,
                size: 24,
                action: onTogglePin
            )
            IconButton(symbol: "trash", help: "删除 (⌥⌫)", role: .destructive, size: 24, action: onDelete)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
        )
    }

    private var glyphSymbol: String {
        if item.isCode { return "chevron.left.forwardslash.chevron.right" }
        if item.smartTag != .general { return item.smartTag.symbolName }
        switch item.category {
        case .link: return "link"
        case .snippet: return "text.bubble.fill"
        case .image: return "photo"
        case .text: return "doc.on.clipboard.fill"
        }
    }

    private var glyphTint: Color {
        if item.isPinned { return .orange }
        if item.isCode { return .cyan }
        if item.smartTag == .foreignText { return .indigo }
        if item.smartTag == .addressContact { return .green }
        if item.smartTag == .credential { return .pink }
        switch item.category {
        case .link, .snippet: return theme.accent
        default: return .secondary
        }
    }
}

private struct DigitChip: View {
    @Environment(\.clipHistoryTheme) private var theme
    let number: Int
    var isHighlighted: Bool = false

    var body: some View {
        Text("⌘\(number)")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(isHighlighted ? theme.accent : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(isHighlighted ? theme.accent.opacity(0.16) : Color.primary.opacity(0.052))
                    .shadow(color: .black.opacity(0.05), radius: 0.5, y: 0.75)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(isHighlighted ? theme.accent.opacity(0.32) : Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

private struct Thumbnail: View {
    let id: Int64
    let data: Data
    var sourceApp: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = ThumbnailCache.shared.thumbnail(for: id, data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
            )

            if let appIcon = ThumbnailCache.shared.appIcon(forSourceApp: sourceApp) {
                SourceAppCornerBadge(icon: appIcon)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

private enum TextHighlight {
    static func attributed(_ raw: String, query: String, accent: Color) -> AttributedString {
        var attr = AttributedString(raw)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, raw.count <= 8_000 else { return attr }

        let tokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ";:/\\")) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return attr }

        for token in tokens {
            var searchStart = raw.startIndex
            while searchStart < raw.endIndex,
                  let range = raw.range(of: token, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<raw.endIndex) {
                if let attrRange = Range(range, in: attr) {
                    attr[attrRange].backgroundColor = accent.opacity(0.24)
                    attr[attrRange].foregroundColor = accent
                }
                searchStart = range.upperBound
            }
        }
        return attr
    }
}
