import SwiftUI

struct AddSnippetView: View {
    @State private var title = ""
    @State private var bodyText = ""
    var onSave: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题（可选）", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $bodyText)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )
            HStack {
                Spacer()
                Button("保存") {
                    onSave(title, bodyText)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
