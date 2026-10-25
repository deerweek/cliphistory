import SwiftUI

/// "动作工坊" (Action Studio) — lets users toggle built-in clipboard transformations
/// and freely add custom AI Prompt or Shell Script actions.
struct ActionStudioView: View {
    @Environment(\.clipHistoryTheme) private var theme
    @ObservedObject var settingsModel: SettingsModel
    var onToast: (String) -> Void

    @State private var editingActionID: String?
    @State private var newTitle = ""
    @State private var newSymbol = "wand.and.stars"
    @State private var newKind: ClipActionKind = .aiPrompt
    @State private var newPayload = ""
    @State private var pasteAfterRun = true

    private let symbolChoices = [
        "wand.and.stars",
        "character.bubble.fill",
        "sparkles",
        "terminal.fill",
        "doc.text.magnifyingglass",
        "text.badge.checkmark",
        "bolt.fill",
        "curlybraces"
    ]

    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                headerBanner

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Label("已安装动作插件（在右侧预览栏显示）", systemImage: "puzzlepiece.extension.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            settingsModel.resetDefaultActions()
                            onToast("已恢复默认动作列表")
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 6) {
                        ForEach($settingsModel.actions) { $action in
                            actionRow(action: $action)
                        }
                    }
                }

                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack {
                        Label(
                            editingActionID == nil ? "自由添加新动作" : "编辑自定义动作",
                            systemImage: editingActionID == nil ? "plus.circle.fill" : "pencil.circle.fill"
                        )
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.accent)

                        Spacer()
                        if editingActionID != nil {
                            Button("取消编辑") {
                                resetEditor()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: Theme.Space.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("动作名称")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("例如：润色为商务语气 / 译为日语 / Base64 解码", text: $newTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(controlBackground)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("动作类型")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $newKind) {
                                Text("AI 指令转换").tag(ClipActionKind.aiPrompt)
                                Text("Shell 脚本").tag(ClipActionKind.shellCommand)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("选择图标")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(symbolChoices, id: \.self) { sym in
                                Button {
                                    newSymbol = sym
                                } label: {
                                    Image(systemName: sym)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(newSymbol == sym ? Color.white : .secondary)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(newSymbol == sym ? theme.accent : Color.primary.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(newKind == .aiPrompt ? "AI 转换提示词（Prompt）" : "Shell 命令（通过 stdin 接收剪贴板文本，输出 stdout）")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if newKind == .aiPrompt {
                                Button("示例：商务润色") {
                                    newTitle = "商务得体润色"
                                    newPayload = "请将以下内容改写为得体、礼貌、简洁的职场商务沟通语气，只输出改写后的正文："
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.accent)
                            } else {
                                Button("示例：行数排序去重") {
                                    newTitle = "按行去重排序"
                                    newPayload = "sort -u"
                                }
                                .font(.system(size: 10.5))
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.accent)
                            }
                        }

                        TextEditor(text: $newPayload)
                            .font(.system(size: 12.5, design: newKind == .shellCommand ? .monospaced : .default))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 76)
                            .background(controlBackground)
                    }

                    HStack {
                        Toggle("执行转换后直接粘贴到目标应用（关闭则预览并复制结果）", isOn: $pasteAfterRun)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanPayload = newPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let editingID = editingActionID {
                                settingsModel.updateCustomAction(
                                    id: editingID,
                                    title: cleanTitle,
                                    symbolName: newSymbol,
                                    kind: newKind,
                                    payload: cleanPayload,
                                    pasteAfterRun: pasteAfterRun
                                )
                                resetEditor()
                                onToast("已保存自定义动作修改")
                            } else {
                                settingsModel.addCustomAction(
                                    title: cleanTitle,
                                    symbolName: newSymbol,
                                    kind: newKind,
                                    payload: cleanPayload,
                                    pasteAfterRun: pasteAfterRun
                                )
                                resetEditor()
                                onToast("已添加自定义动作插件")
                            }
                        } label: {
                            Label(
                                editingActionID == nil ? "添加到动作栏" : "保存动作修改",
                                systemImage: editingActionID == nil ? "plus" : "checkmark"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdd)
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 12) {
            KindGlyph(symbol: "wand.and.stars", tint: theme.accent, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("可插拔动作工坊（Action Pipeline）")
                    .font(.system(size: 13.5, weight: .bold))
                Text("复制任何内容后，可在预览栏一键翻译、提取单号、格式化 JSON，或运行你自定义的 AI 指令与 Shell 脚本。点击动作右侧标签可切换“仅预览/复制”或“转换并粘贴”。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.accent.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private func actionRow(action: Binding<ClipActionDescriptor>) -> some View {
        let item = action.wrappedValue
        return HStack(spacing: 10) {
            Toggle("", isOn: action.isEnabled)
                .labelsHidden()
                .controlSize(.small)

            KindGlyph(symbol: item.symbolName, tint: item.isEnabled ? theme.accent : .secondary, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(item.isEnabled ? .primary : .secondary)
                    Badge(text: item.kind.title, filled: false)
                }
                if !item.payload.isEmpty && item.kind != .builtIn {
                    Text(item.payload)
                        .font(.system(size: 10.5, design: item.kind == .shellCommand ? .monospaced : .default))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                action.wrappedValue.pasteAfterRun.toggle()
            } label: {
                Badge(
                    text: item.pasteAfterRun ? "转换并粘贴" : "预览并复制",
                    symbol: item.pasteAfterRun ? "arrow.turn.down.left" : "eye",
                    tint: item.pasteAfterRun ? theme.accent : .secondary,
                    filled: item.pasteAfterRun
                )
            }
            .buttonStyle(.plain)
            .help("点击切换执行此动作后的行为：直接粘贴到目标应用，或在预览栏展示并复制结果")

            if item.kind != .builtIn {
                IconButton(
                    symbol: "pencil",
                    help: "编辑此自定义动作",
                    isActive: editingActionID == item.id,
                    activeTint: theme.accent
                ) {
                    editingActionID = item.id
                    newTitle = item.title
                    newSymbol = item.symbolName
                    newKind = item.kind
                    newPayload = item.payload
                    pasteAfterRun = item.pasteAfterRun
                }

                IconButton(symbol: "trash", help: "删除此自定义动作", role: .destructive) {
                    if editingActionID == item.id {
                        resetEditor()
                    }
                    settingsModel.removeAction(id: item.id)
                    onToast("已移除动作")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(editingActionID == item.id ? theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 0.75)
                )
        )
    }

    private func resetEditor() {
        editingActionID = nil
        newTitle = ""
        newPayload = ""
        newSymbol = "wand.and.stars"
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(Theme.controlFill)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}
