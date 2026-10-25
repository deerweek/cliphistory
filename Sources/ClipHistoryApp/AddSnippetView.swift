import AppKit
import SwiftUI

struct AddSnippetView: View {
    @Environment(\.clipHistoryTheme) private var theme

    let editingItem: ClipItem?
    var onSave: (Int64?, String, String, ItemKind, String?, SmartArchiveTag) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var kind: ItemKind
    @State private var triggerCode: String
    @State private var smartTag: SmartArchiveTag
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case trigger
        case body
    }

    init(
        editingItem: ClipItem? = nil,
        onSave: @escaping (Int64?, String, String, ItemKind, String?, SmartArchiveTag) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editingItem = editingItem
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: editingItem?.title ?? "")
        _bodyText = State(initialValue: editingItem?.body ?? "")
        _kind = State(initialValue: editingItem?.kind ?? .snippet)
        _triggerCode = State(initialValue: editingItem?.triggerCode ?? "")
        _smartTag = State(initialValue: editingItem?.smartTag ?? .general)
    }

    private var isImageItem: Bool {
        editingItem?.contentType == .image
    }

    private var trimmedTrigger: String {
        triggerCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTriggerInvalid: Bool {
        !isImageItem && !trimmedTrigger.isEmpty && trimmedTrigger.count < 2
    }

    private var canSave: Bool {
        if isTriggerInvalid { return false }
        if isImageItem { return true }
        return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lineCount: Int {
        guard !bodyText.isEmpty else { return 0 }
        return max(1, bodyText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                KindGlyph(
                    symbol: editingItem == nil ? "plus.bubble.fill" : (isImageItem ? "photo.badge.plus" : "slider.horizontal.3"),
                    tint: theme.accent,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(editingItem == nil ? "新建快捷回复" : (isImageItem ? "编辑图片备注" : "编辑条目与触发码"))
                        .font(.system(size: 14, weight: .bold))
                    Text("设置触发短码（如 ;dz）后，在任意应用打字敲出短码即可自动展开上屏。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isImageItem {
                    Picker("", selection: $kind) {
                        Text("快捷回复").tag(ItemKind.snippet)
                        Text("普通历史").tag(ItemKind.history)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 164)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                            .strokeBorder(Theme.specularStroke, lineWidth: 0.75)
                    )
            )

            HStack(spacing: Theme.Space.md) {
                field(title: "自定义标题", subtitle: "可选 · 用于快速检索") {
                    TextField("例如：公司发票抬头 / 收货地址", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($focusedField, equals: .title)
                        .onSubmit {
                            if canSave { submit() }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(controlBackground)
                }

                if !isImageItem {
                    field(title: "输入法短码", subtitle: isTriggerInvalid ? "至少 2 个字符" : "如 ;dz") {
                        TextField("例如：;dz", text: $triggerCode)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .focused($focusedField, equals: .trigger)
                            .onSubmit {
                                if canSave { submit() }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(controlBackground)
                    }
                    .frame(width: 145)
                }

                field(title: "智能归档夹", subtitle: nil) {
                    Picker("", selection: $smartTag) {
                        ForEach(SmartArchiveTag.allCases, id: \.self) { tag in
                            Label(tag.title, systemImage: tag.symbolName).tag(tag)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
            }

            if isImageItem, let data = editingItem?.imageData {
                field(title: "图片预览", subtitle: editingItem?.body) {
                    HStack {
                        Spacer()
                        if let img = ThumbnailCache.shared.previewImage(for: editingItem?.id ?? 0, data: data) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.md)
                    .background(controlBackground)
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("正文内容")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("支持动态变量：")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)

                        ForEach(["{{date}}", "{{time}}", "{{datetime}}", "{{clipboard}}"], id: \.self) { token in
                            Button {
                                bodyText += token
                            } label: {
                                Text(token)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(theme.accent.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("插入动态占位符 \(token)")
                        }

                        Spacer()
                        Button {
                            if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                                bodyText = clip
                            }
                        } label: {
                            Label("从剪贴板填入", systemImage: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                    }

                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("输入常用话术、地址或代码片段（按 ↵ 正常换行，按 ⌘↵ 保存）…")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Theme.Space.md + 1)
                                .padding(.vertical, Theme.Space.md)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $bodyText)
                            .font(.system(size: 13, design: ContentClassifier.isCodeLike(bodyText) ? .monospaced : .default))
                            .focused($focusedField, equals: .body)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, Theme.Space.sm)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                    .background(controlBackground)
                }
            }

            HStack(spacing: Theme.Space.md) {
                if !isImageItem {
                    Text("\(bodyText.count) 字 · \(lineCount) 行")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Spacer()
                ShortcutHint(keys: "Esc", label: "取消")
                ShortcutHint(keys: "⌘↵", label: "保存")
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button {
                    submit()
                } label: {
                    Label(editingItem == nil ? "保存快捷回复" : "保存修改", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if editingItem == nil {
                focusedField = .title
            } else if isImageItem {
                focusedField = .title
            } else {
                focusedField = .body
            }
        }
    }

    private func submit() {
        guard canSave else { return }
        let cleanTrigger = triggerCode.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            editingItem?.id,
            title,
            bodyText,
            kind,
            cleanTrigger.isEmpty ? nil : cleanTrigger,
            smartTag
        )
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(Theme.controlFill)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func field<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            content()
        }
    }
}
