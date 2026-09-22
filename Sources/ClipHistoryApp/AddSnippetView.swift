import SwiftUI

struct AddSnippetView: View {
    @State private var title = ""
    @State private var bodyText = ""
    var onSave: (String, String) -> Void

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            field(title: "标题", subtitle: "可选") {
                TextField("例如：常用地址", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 8)
                    .background(controlBackground)
            }

            field(title: "内容", subtitle: nil) {
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("输入常用的一段话，之后一键粘贴。")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Space.md + 1)
                            .padding(.vertical, Theme.Space.md)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $bodyText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, Theme.Space.sm)
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                .background(controlBackground)
            }

            HStack(spacing: Theme.Space.md) {
                Text("\(bodyText.count) 字")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                ShortcutHint(keys: "↵", label: "保存")
                Button {
                    onSave(title, bodyText)
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedBody.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.xs) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }
}
