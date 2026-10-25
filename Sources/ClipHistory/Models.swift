import Foundation

/// Where an item came from / how it behaves.
public enum ItemKind: String, Sendable, Equatable, Codable {
    case history
    case snippet
}

/// What the clipboard item actually contains.
public enum ContentType: String, Sendable, Equatable, Codable {
    case text
    case link
    case image
}

/// User-facing grouping used for the filter bar and row badges.
public enum ClipCategory: String, CaseIterable, Sendable, Equatable {
    case text
    case link
    case image
    case snippet

    public var title: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        case .snippet: return "快捷回复"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .snippet: return "text.bubble"
        }
    }
}

/// Smart semantic archive folders automatically assigned by local NLP or Jev model.
public enum SmartArchiveTag: String, CaseIterable, Sendable, Equatable, Codable {
    case general = "general"
    case addressContact = "address_contact"
    case codeCommand = "code_command"
    case credential = "credential"
    case foreignText = "foreign_text"
    case workChat = "work_chat"

    public var title: String {
        switch self {
        case .general: return "常规"
        case .addressContact: return "地址与联系"
        case .codeCommand: return "代码与命令"
        case .credential: return "验证码与密钥"
        case .foreignText: return "外语文本"
        case .workChat: return "工作沟通"
        }
    }

    public var symbolName: String {
        switch self {
        case .general: return "doc.text"
        case .addressContact: return "mappin.and.ellipse"
        case .codeCommand: return "chevron.left.forwardslash.chevron.right"
        case .credential: return "key.fill"
        case .foreignText: return "character.book.closed.fill"
        case .workChat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

public struct ClipItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: ItemKind
    public var contentType: ContentType
    public var body: String
    public var title: String?
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Raw bytes for image items (PNG). `nil` for text/link items.
    public var imageData: Data?
    /// Number of times this item has been pasted/used.
    public var useCount: Int
    /// Bundle ID or display name of the source application where this was copied.
    public var sourceApp: String?
    /// Automatically or Jev-assigned smart archive tag.
    public var smartTag: SmartArchiveTag
    /// Optional short trigger code for IME/typing auto-expansion (e.g. `;dz`, `;fp`).
    public var triggerCode: String?

    public init(
        id: Int64,
        kind: ItemKind,
        contentType: ContentType = .text,
        body: String,
        title: String?,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date,
        imageData: Data? = nil,
        useCount: Int = 0,
        sourceApp: String? = nil,
        smartTag: SmartArchiveTag = .general,
        triggerCode: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.contentType = contentType
        self.body = body
        self.title = title
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageData = imageData
        self.useCount = useCount
        self.sourceApp = sourceApp
        self.smartTag = smartTag
        self.triggerCode = triggerCode
    }

    /// Grouping used by the filter bar. Precedence: image > snippet > link > text.
    public var category: ClipCategory {
        if contentType == .image { return .image }
        if kind == .snippet { return .snippet }
        if contentType == .link { return .link }
        return .text
    }

    public var hasCustomTitle: Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasTriggerCode: Bool {
        guard let triggerCode else { return false }
        return !triggerCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let nonEmptyLine = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let collapsed = nonEmptyLine ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return contentType == .image ? "图片" : collapsed
        }
        if collapsed.count <= 80 {
            return collapsed
        }
        return String(collapsed.prefix(80)) + "…"
    }

    /// Secondary preview text that skips the first line when no custom title is set.
    public var secondaryPreviewText: String {
        if contentType == .image {
            if let ocr = imageOCRText {
                let singleLine = ocr.split(whereSeparator: \.isNewline).joined(separator: " ")
                return "识别文字：\(singleLine)"
            }
            return hasCustomTitle ? imageDimensionsLabel : ""
        }
        if hasCustomTitle {
            return body.trimmingCharacters(in: .newlines)
        }
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return ""
        }
        let remaining = lines[(lines.index(after: firstNonEmptyIndex))...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return remaining
    }

    public var isCode: Bool {
        contentType == .text && (smartTag == .codeCommand || ContentClassifier.isCodeLike(body))
    }

    public var isForeignLanguage: Bool {
        contentType == .text && !isCode && ContentClassifier.looksLikeForeignText(body)
    }

    public var isChineseText: Bool {
        contentType == .text && ContentClassifier.containsChinese(body)
    }

    public var hexColor: (r: Double, g: Double, b: Double, hex: String)? {
        contentType == .text ? ContentClassifier.extractHexColor(body) : nil
    }

    public var linkHost: String? {
        contentType == .link ? ContentClassifier.extractHost(body) : nil
    }

    /// For image items, the first line of `body` holds the dimensions label (e.g. "图片 · 800×600"),
    /// while subsequent lines (if any) hold Vision OCR recognized text.
    public var imageDimensionsLabel: String {
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        return firstLine.isEmpty ? "图片" : firstLine
    }

    /// OCR text recognized inside an image item, if any.
    public var imageOCRText: String? {
        guard contentType == .image else { return nil }
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.count > 1 else { return nil }
        let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Extracted verification code or tracking number when this item is a credential/OTP message.
    public var extractedCredentialCode: String? {
        guard contentType == .text, smartTag == .credential else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let extracted = ClipActionEngine.runBuiltIn(id: "extract_digits", on: trimmed),
              extracted.count < trimmed.count else {
            return nil
        }
        return extracted
    }

    public var lineCount: Int {
        guard contentType != .image, !body.isEmpty else { return 0 }
        return max(1, body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
    }

    public var characterCount: Int {
        contentType == .image ? 0 : body.count
    }

    /// Concise metadata summary for list rows and inspector headers.
    public var metadataSummary: String {
        switch contentType {
        case .image:
            if let bytes = imageData?.count, bytes > 0 {
                return Self.formatByteCount(bytes)
            }
            return body
        case .link:
            return linkHost ?? "网页链接"
        case .text:
            if let hex = hexColor {
                return "颜色 \(hex.hex)"
            }
            if lineCount > 1 {
                return "\(characterCount) 字 · \(lineCount) 行"
            }
            return "\(characterCount) 字"
        }
    }

    public func relativeTime(from now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(updatedAt))
        if delta < 45 {
            return "刚刚"
        }
        let minutes = Int(delta / 60)
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }
        let hours = Int(delta / 3600)
        if hours < 24 {
            return "\(hours) 小时前"
        }
        let days = Int(delta / 86_400)
        if days == 1 {
            return "昨天"
        }
        if days < 30 {
            return "\(days) 天前"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: updatedAt)
    }

    public static func formatByteCount(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

public enum StoreError: Error, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case notFound
}
