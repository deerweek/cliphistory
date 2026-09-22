import Foundation

public enum ItemKind: String, Sendable, Equatable {
    case history
    case snippet
}

public struct ClipItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: ItemKind
    public var body: String
    public var title: String?
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64,
        kind: ItemKind,
        body: String,
        title: String?,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.body = body
        self.title = title
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        let collapsed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
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
