import Foundation

/// Where an item came from / how it behaves.
public enum ItemKind: String, Sendable, Equatable {
    case history
    case snippet
}

/// What the clipboard item actually contains.
public enum ContentType: String, Sendable, Equatable {
    case text
    case link
    case image
}

/// User-facing grouping used for the filter bar and row badges. Derived from an
/// item's kind + content type so it always stays in sync with storage.
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

    /// SF Symbol name (used by the macOS UI; kept here so category and glyph stay together).
    public var symbolName: String {
        switch self {
        case .text: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .snippet: return "text.bubble"
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

    public init(
        id: Int64,
        kind: ItemKind,
        contentType: ContentType = .text,
        body: String,
        title: String?,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date,
        imageData: Data? = nil
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
    }

    /// Grouping used by the filter bar. Precedence: image > snippet > link > text.
    public var category: ClipCategory {
        if contentType == .image { return .image }
        if kind == .snippet { return .snippet }
        if contentType == .link { return .link }
        return .text
    }

    public var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        let collapsed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return contentType == .image ? "图片" : collapsed
        }
        if collapsed.count <= 80 {
            return collapsed
        }
        return String(collapsed.prefix(80)) + "…"
    }
}

public enum StoreError: Error, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case notFound
}
