import Foundation

/// Kind of transformation an action performs on a clipboard item.
public enum ClipActionKind: String, Codable, CaseIterable, Sendable, Equatable {
    case builtIn
    case aiPrompt
    case shellCommand

    public var title: String {
        switch self {
        case .builtIn: return "内置工具"
        case .aiPrompt: return "AI 指令转换"
        case .shellCommand: return "Shell 脚本"
        }
    }
}

/// A pluggable action that transforms or processes a `ClipItem` and optionally pastes the result.
public struct ClipActionDescriptor: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var symbolName: String
    public var kind: ClipActionKind
    /// For `.aiPrompt`, the system/instruction prompt. For `.shellCommand`, the shell command receiving stdin.
    public var payload: String
    public var isEnabled: Bool
    /// Whether executing this action should immediately paste the transformed text into the target app.
    public var pasteAfterRun: Bool

    public init(
        id: String,
        title: String,
        symbolName: String,
        kind: ClipActionKind,
        payload: String = "",
        isEnabled: Bool = true,
        pasteAfterRun: Bool = true
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.kind = kind
        self.payload = payload
        self.isEnabled = isEnabled
        self.pasteAfterRun = pasteAfterRun
    }
}

/// Executes built-in synchronous transformations, template expansions, and manages custom actions.
public enum ClipActionEngine {

    public static let defaultBuiltInActions: [ClipActionDescriptor] = [
        ClipActionDescriptor(
            id: "translate_auto",
            title: "中英互译",
            symbolName: "character.bubble.fill",
            kind: .builtIn,
            payload: "auto",
            isEnabled: true,
            pasteAfterRun: false
        ),
        ClipActionDescriptor(
            id: "clean_newlines",
            title: "合并断行",
            symbolName: "paragraphsign",
            kind: .builtIn,
            payload: "",
            isEnabled: true,
            pasteAfterRun: false
        ),
        ClipActionDescriptor(
            id: "format_json",
            title: "美化 JSON",
            symbolName: "curlybraces",
            kind: .builtIn,
            payload: "",
            isEnabled: true,
            pasteAfterRun: false
        ),
        ClipActionDescriptor(
            id: "extract_digits",
            title: "提取验证码/单号",
            symbolName: "number.square",
            kind: .builtIn,
            payload: "",
            isEnabled: true,
            pasteAfterRun: true
        ),
        ClipActionDescriptor(
            id: "strip_spaces",
            title: "去除全部空格",
            symbolName: "scissors",
            kind: .builtIn,
            payload: "",
            isEnabled: true,
            pasteAfterRun: false
        ),
        ClipActionDescriptor(
            id: "url_decode",
            title: "URL 解码",
            symbolName: "link.badge.plus",
            kind: .builtIn,
            payload: "",
            isEnabled: true,
            pasteAfterRun: false
        )
    ]

    /// Expands dynamic placeholders in snippets such as `{{date}}`, `{{time}}`, `{{datetime}}`, `{{clipboard}}`.
    public static func expandTemplateVariables(
        in text: String,
        currentClipboard: String? = nil,
        now: Date = Date()
    ) -> String {
        guard text.contains("{{") && text.contains("}}") else { return text }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let fullFmt = DateFormatter()
        fullFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var output = text
        output = output.replacingOccurrences(of: "{{date}}", with: dateFmt.string(from: now))
        output = output.replacingOccurrences(of: "{{time}}", with: timeFmt.string(from: now))
        output = output.replacingOccurrences(of: "{{datetime}}", with: fullFmt.string(from: now))
        if let currentClipboard {
            output = output.replacingOccurrences(of: "{{clipboard}}", with: currentClipboard)
        }
        return output
    }

    /// Executes synchronous built-in transformations on `text`.
    public static func runBuiltIn(id: String, on text: String) -> String? {
        switch id {
        case "clean_newlines":
            // Joins broken single newlines (e.g. copied from PDFs) while preserving double-newline paragraphs.
            let paragraphs = text.components(separatedBy: "\n\n")
            let cleaned = paragraphs.map { para in
                para.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }.joined(separator: "\n\n")
            return cleaned.isEmpty ? text : cleaned

        case "format_json":
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: pretty, encoding: .utf8) else {
                return nil
            }
            return str

        case "extract_digits":
            // Extracts 4-to-20 char alphanumeric verification codes or tracking numbers
            let pattern = #"[A-Za-z0-9]{4,24}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, range: range).compactMap { match -> String? in
                guard let r = Range(match.range, in: text) else { return nil }
                let candidate = String(text[r])
                // Prefer tokens that contain at least one digit
                return candidate.contains(where: \.isNumber) ? candidate : nil
            }
            // Prefer 4-8 digit verification codes first, otherwise longest tracking number
            if let code = matches.first(where: { (4...8).contains($0.count) && $0.allSatisfy(\.isNumber) }) {
                return code
            }
            return matches.max(by: { $0.count < $1.count })

        case "strip_spaces":
            return String(text.filter { !$0.isWhitespace && !$0.isNewline })

        case "url_decode":
            return text.removingPercentEncoding ?? text

        default:
            return nil
        }
    }
}
