import Foundation

public final class Store: @unchecked Sendable {
    private let database: Database
    private let lock = NSLock()

    /// Canonical column order shared by every SELECT and `decodeItem`.
    private static let columns =
        "id, kind, content_type, body, title, is_pinned, created_at, updated_at, data, use_count, source_app, smart_tag, trigger_code"

    public init(path: String) throws {
        database = try Database(path: path)
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                content_type TEXT NOT NULL DEFAULT 'text',
                body TEXT NOT NULL,
                title TEXT,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                data BLOB,
                use_count INTEGER NOT NULL DEFAULT 0,
                source_app TEXT,
                smart_tag TEXT NOT NULL DEFAULT 'general',
                trigger_code TEXT
            )
            """
        )
        try migrate()
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_kind_updated ON items(kind, updated_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_body_kind ON items(body, kind)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_content_type ON items(content_type)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_smart_tag ON items(smart_tag)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_trigger_code ON items(trigger_code)"
        )
    }

    private func migrate() throws {
        let existing = try database.query("PRAGMA table_info(items)").compactMap { row -> String? in
            guard row.count > 1, case .text(let name) = row[1] else { return nil }
            return name
        }
        if !existing.contains("content_type") {
            try database.execute("ALTER TABLE items ADD COLUMN content_type TEXT NOT NULL DEFAULT 'text'")
        }
        if !existing.contains("data") {
            try database.execute("ALTER TABLE items ADD COLUMN data BLOB")
        }
        if !existing.contains("use_count") {
            try database.execute("ALTER TABLE items ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0")
        }
        if !existing.contains("source_app") {
            try database.execute("ALTER TABLE items ADD COLUMN source_app TEXT")
        }
        if !existing.contains("smart_tag") {
            try database.execute("ALTER TABLE items ADD COLUMN smart_tag TEXT NOT NULL DEFAULT 'general'")
        }
        if !existing.contains("trigger_code") {
            try database.execute("ALTER TABLE items ADD COLUMN trigger_code TEXT")
        }
        let textCandidates = try database.query(
            """
            SELECT id, body FROM items
            WHERE content_type = 'text'
              AND (lower(body) LIKE '%http://%' OR lower(body) LIKE '%https://%' OR lower(body) LIKE '%www.%' OR body LIKE '%.%')
            """
        )
        for row in textCandidates {
            if row.count >= 2,
               case .int(let id) = row[0],
               case .text(let body) = row[1],
               ContentClassifier.classify(body) == .link {
                try database.execute(
                    "UPDATE items SET content_type = 'link' WHERE id = ?",
                    [.int(id)]
                )
            }
        }
    }

    @discardableResult
    public func recordHistory(
        _ body: String,
        sourceApp: String? = nil,
        smartTag: SmartArchiveTag? = nil,
        now: Date = Date()
    ) throws -> ClipItem {
        try synced {
            if let existing = try fetchOne(
                """
                SELECT \(Self.columns)
                FROM items
                WHERE kind = ? AND content_type != 'image' AND body = ?
                LIMIT 1
                """,
                [.text(ItemKind.history.rawValue), .text(body)]
            ) {
                try database.execute(
                    """
                    UPDATE items
                    SET updated_at = ?, source_app = COALESCE(?, source_app)
                    WHERE id = ?
                    """,
                    [
                        .double(now.timeIntervalSince1970),
                        sourceApp.map { .text($0) } ?? .null,
                        .int(existing.id)
                    ]
                )
                let item = try itemByID(existing.id)
                try checkpoint()
                return item
            }

            let contentType = ContentClassifier.classify(body)
            let resolvedTag = smartTag ?? ContentClassifier.classifySmartTag(body, contentType: contentType)
            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at, use_count, source_app, smart_tag)
                VALUES (?, ?, ?, NULL, 0, ?, ?, 0, ?, ?)
                """,
                [
                    .text(ItemKind.history.rawValue),
                    .text(contentType.rawValue),
                    .text(body),
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970),
                    sourceApp.map { .text($0) } ?? .null,
                    .text(resolvedTag.rawValue)
                ]
            )
            let item = try itemByID(database.lastInsertRowID)
            try checkpoint()
            return item
        }
    }

    @discardableResult
    public func recordImage(
        _ data: Data,
        width: Int = 0,
        height: Int = 0,
        sourceApp: String? = nil,
        now: Date = Date()
    ) throws -> ClipItem {
        try synced {
            if let existing = try fetchOne(
                """
                SELECT \(Self.columns)
                FROM items
                WHERE kind = ? AND content_type = 'image' AND data = ?
                LIMIT 1
                """,
                [.text(ItemKind.history.rawValue), .blob(data)]
            ) {
                try database.execute(
                    "UPDATE items SET updated_at = ?, source_app = COALESCE(?, source_app) WHERE id = ?",
                    [
                        .double(now.timeIntervalSince1970),
                        sourceApp.map { .text($0) } ?? .null,
                        .int(existing.id)
                    ]
                )
                let item = try itemByID(existing.id)
                try checkpoint()
                return item
            }

            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at, data, use_count, source_app, smart_tag)
                VALUES (?, 'image', ?, NULL, 0, ?, ?, ?, 0, ?, 'general')
                """,
                [
                    .text(ItemKind.history.rawValue),
                    .text(Self.imageDescriptor(width: width, height: height)),
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970),
                    .blob(data),
                    sourceApp.map { .text($0) } ?? .null
                ]
            )
            let item = try itemByID(database.lastInsertRowID)
            try checkpoint()
            return item
        }
    }

    public static func imageDescriptor(width: Int, height: Int) -> String {
        (width > 0 && height > 0) ? "图片 · \(width)×\(height)" : "图片"
    }

    @discardableResult
    public func addSnippet(
        title: String?,
        body: String,
        triggerCode: String? = nil,
        smartTag: SmartArchiveTag? = nil,
        now: Date = Date()
    ) throws -> ClipItem {
        try synced {
            let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
            let trimmedCode = triggerCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedCode = trimmedCode.isEmpty ? nil : trimmedCode
            let contentType = ContentClassifier.classify(body)
            let resolvedTag = smartTag ?? ContentClassifier.classifySmartTag(body, contentType: contentType)

            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at, use_count, smart_tag, trigger_code)
                VALUES (?, ?, ?, ?, 0, ?, ?, 0, ?, ?)
                """,
                [
                    .text(ItemKind.snippet.rawValue),
                    .text(contentType.rawValue),
                    .text(body),
                    resolvedTitle.map { .text($0) } ?? .null,
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970),
                    .text(resolvedTag.rawValue),
                    resolvedCode.map { .text($0) } ?? .null
                ]
            )
            let item = try itemByID(database.lastInsertRowID)
            try checkpoint()
            return item
        }
    }

    @discardableResult
    public func updateItem(
        id: Int64,
        title: String?,
        body: String,
        kind: ItemKind? = nil,
        triggerCode: String? = nil,
        smartTag: SmartArchiveTag? = nil,
        now: Date = Date()
    ) throws -> ClipItem {
        try synced {
            let current = try itemByID(id)
            return try updateItemUnlocked(
                current: current,
                title: title,
                body: body,
                kind: kind ?? current.kind,
                triggerCode: triggerCode ?? current.triggerCode,
                smartTag: smartTag ?? current.smartTag,
                now: now
            )
        }
    }

    @discardableResult
    public func convertToSnippet(id: Int64, title: String? = nil, now: Date = Date()) throws -> ClipItem {
        try synced {
            let current = try itemByID(id)
            let finalTitle = title ?? current.title
            return try updateItemUnlocked(
                current: current,
                title: finalTitle,
                body: current.body,
                kind: .snippet,
                triggerCode: current.triggerCode,
                smartTag: current.smartTag,
                now: now
            )
        }
    }

    /// Checks whether a text history item with the exact body already exists.
    public func hasHistoryItem(body: String) throws -> Bool {
        try synced {
            let rows = try database.query(
                "SELECT 1 FROM items WHERE kind = ? AND content_type != 'image' AND body = ? LIMIT 1",
                [.text(ItemKind.history.rawValue), .text(body)]
            )
            return !rows.isEmpty
        }
    }

    /// Checks whether an image history item with the exact PNG data already exists.
    public func hasImageItem(data: Data) throws -> Bool {
        try synced {
            let rows = try database.query(
                "SELECT 1 FROM items WHERE kind = ? AND content_type = 'image' AND data = ? LIMIT 1",
                [.text(ItemKind.history.rawValue), .blob(data)]
            )
            return !rows.isEmpty
        }
    }

    /// Increments `use_count` when an item is pasted or expanded via trigger code,
    /// preserving `updated_at` so list order does not jump under the user's cursor.
    public func recordUse(id: Int64, now: Date = Date()) throws {
        try synced {
            try database.execute(
                "UPDATE items SET use_count = use_count + 1 WHERE id = ?",
                [.int(id)]
            )
            try checkpoint()
        }
    }

    /// Updates the smart archive tag (e.g. when Jev model refines the classification).
    public func updateSmartTag(id: Int64, tag: SmartArchiveTag) throws {
        try synced {
            try database.execute(
                "UPDATE items SET smart_tag = ? WHERE id = ?",
                [.text(tag.rawValue), .int(id)]
            )
            try checkpoint()
        }
    }

    /// Stores OCR-recognized text on an image item so screenshots become searchable by their text content.
    public func updateImageOCRText(id: Int64, ocrText: String) throws {
        let cleaned = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        try synced {
            guard let item = try? itemByID(id), item.contentType == .image else { return }
            let header = item.imageDimensionsLabel
            let combined = header + "\n" + String(cleaned.prefix(10_000))
            try database.execute(
                "UPDATE items SET body = ? WHERE id = ?",
                [.text(combined), .int(id)]
            )
            try checkpoint()
        }
    }

    /// Compacts the SQLite database file and truncates the WAL journal.
    public func vacuum() throws {
        try synced {
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            try database.execute("VACUUM")
        }
    }

    // MARK: - JSON Backup Export & Import

    public struct BackupItem: Codable, Sendable, Equatable {
        public var kind: ItemKind
        public var contentType: ContentType
        public var body: String
        public var title: String?
        public var isPinned: Bool
        public var createdAt: Date
        public var updatedAt: Date
        public var useCount: Int
        public var sourceApp: String?
        public var smartTag: SmartArchiveTag
        public var triggerCode: String?

        public init(
            kind: ItemKind,
            contentType: ContentType,
            body: String,
            title: String?,
            isPinned: Bool,
            createdAt: Date,
            updatedAt: Date,
            useCount: Int,
            sourceApp: String?,
            smartTag: SmartArchiveTag,
            triggerCode: String?
        ) {
            self.kind = kind
            self.contentType = contentType
            self.body = body
            self.title = title
            self.isPinned = isPinned
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.useCount = useCount
            self.sourceApp = sourceApp
            self.smartTag = smartTag
            self.triggerCode = triggerCode
        }
    }

    public struct BackupPayload: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var items: [BackupItem]
        public var actions: [ClipActionDescriptor]?

        public init(
            version: Int = 1,
            exportedAt: Date = Date(),
            items: [BackupItem],
            actions: [ClipActionDescriptor]? = nil
        ) {
            self.version = version
            self.exportedAt = exportedAt
            self.items = items
            self.actions = actions
        }
    }

    /// Exports all snippets, pinned records, and recent text/link history items into a portable JSON payload.
    public func exportBackup(actions: [ClipActionDescriptor]? = nil) throws -> Data {
        let allItems = try items()
        let exportable = allItems.compactMap { item -> BackupItem? in
            guard item.contentType != .image else { return nil }
            return BackupItem(
                kind: item.kind,
                contentType: item.contentType,
                body: item.body,
                title: item.title,
                isPinned: item.isPinned,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                useCount: item.useCount,
                sourceApp: item.sourceApp,
                smartTag: item.smartTag,
                triggerCode: item.triggerCode
            )
        }
        let payload = BackupPayload(version: 1, exportedAt: Date(), items: exportable, actions: actions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Imports snippets, pinned records, and history items from a JSON backup payload without duplicating existing items.
    public func importBackup(_ data: Data) throws -> (importedCount: Int, actions: [ClipActionDescriptor]?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var importedCount = 0

        for entry in payload.items.reversed() {
            let trimmed = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if entry.kind == .snippet {
                let item = try addSnippet(
                    title: entry.title,
                    body: entry.body,
                    triggerCode: entry.triggerCode,
                    smartTag: entry.smartTag,
                    now: entry.updatedAt
                )
                if entry.isPinned && !item.isPinned {
                    try setPinned(id: item.id, pinned: true)
                }
                importedCount += 1
            } else {
                if try !hasHistoryItem(body: entry.body) {
                    let item = try recordHistory(entry.body, sourceApp: entry.sourceApp, now: entry.updatedAt)
                    if entry.isPinned {
                        try setPinned(id: item.id, pinned: true)
                    }
                    if entry.title != nil || entry.triggerCode != nil || entry.smartTag != item.smartTag {
                        _ = try updateItem(
                            id: item.id,
                            title: entry.title,
                            body: entry.body,
                            kind: .history,
                            triggerCode: entry.triggerCode,
                            smartTag: entry.smartTag,
                            now: entry.updatedAt
                        )
                    }
                    importedCount += 1
                }
            }
        }
        return (importedCount, payload.actions)
    }

    /// Returns all snippets (and pinned items with trigger codes) for fast IME expansion and Jev reply matching.
    public func snippets() throws -> [ClipItem] {
        try synced {
            let sql = """
            SELECT \(Self.columns)
            FROM items
            WHERE kind = 'snippet' OR (trigger_code IS NOT NULL AND trigger_code != '')
            ORDER BY is_pinned DESC, use_count DESC, updated_at DESC
            """
            return try database.query(sql).map(Self.decodeItem)
        }
    }

    private func updateItemUnlocked(
        current: ClipItem,
        title: String?,
        body: String,
        kind: ItemKind,
        triggerCode: String?,
        smartTag: SmartArchiveTag,
        now: Date
    ) throws -> ClipItem {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        let trimmedCode = triggerCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedCode = trimmedCode.isEmpty ? nil : trimmedCode
        let resolvedContentType: ContentType = current.contentType == .image
            ? .image
            : ContentClassifier.classify(body)
        let resolvedBody = current.contentType == .image ? current.body : body

        try database.execute(
            """
            UPDATE items
            SET kind = ?, content_type = ?, body = ?, title = ?, trigger_code = ?, smart_tag = ?, updated_at = ?
            WHERE id = ?
            """,
            [
                .text(kind.rawValue),
                .text(resolvedContentType.rawValue),
                .text(resolvedBody),
                resolvedTitle.map { .text($0) } ?? .null,
                resolvedCode.map { .text($0) } ?? .null,
                .text(smartTag.rawValue),
                .double(now.timeIntervalSince1970),
                .int(current.id)
            ]
        )
        let updated = try itemByID(current.id)
        try checkpoint()
        return updated
    }

    public func totalCount() throws -> Int {
        try synced {
            let rows = try database.query("SELECT COUNT(*) FROM items")
            if let first = rows.first, let cell = first.first, case .int(let count) = cell {
                return Int(count)
            }
            return 0
        }
    }

    public func togglePin(id: Int64) throws {
        try synced {
            try database.execute(
                "UPDATE items SET is_pinned = CASE is_pinned WHEN 1 THEN 0 ELSE 1 END WHERE id = ?",
                [.int(id)]
            )
            guard try exists(id: id) else { throw StoreError.notFound }
        }
    }

    public func setPinned(id: Int64, pinned: Bool) throws {
        try synced {
            try database.execute(
                "UPDATE items SET is_pinned = ? WHERE id = ?",
                [.int(pinned ? 1 : 0), .int(id)]
            )
            guard try exists(id: id) else { throw StoreError.notFound }
        }
    }

    public func delete(id: Int64) throws {
        try synced {
            try database.execute("DELETE FROM items WHERE id = ?", [.int(id)])
        }
    }

    public func clearUnpinnedHistory() throws {
        try synced {
            try database.execute(
                "DELETE FROM items WHERE kind = ? AND is_pinned = 0",
                [.text(ItemKind.history.rawValue)]
            )
        }
    }

    public func cleanup(maxHistory: Int?, maxAgeDays: Int?, now: Date = Date()) throws {
        try synced {
            if let maxHistory {
                try database.execute(
                    """
                    DELETE FROM items
                    WHERE kind = ?
                      AND is_pinned = 0
                      AND id NOT IN (
                          SELECT id FROM items
                          WHERE kind = ? AND is_pinned = 0
                          ORDER BY updated_at DESC, id DESC
                          LIMIT ?
                      )
                    """,
                    [
                        .text(ItemKind.history.rawValue),
                        .text(ItemKind.history.rawValue),
                        .int(Int64(maxHistory))
                    ]
                )
            }

            if let maxAgeDays {
                let cutoff = now.addingTimeInterval(TimeInterval(-maxAgeDays * 86_400))
                try database.execute(
                    """
                    DELETE FROM items
                    WHERE kind = ? AND is_pinned = 0 AND updated_at < ?
                    """,
                    [.text(ItemKind.history.rawValue), .double(cutoff.timeIntervalSince1970)]
                )
            }
        }
    }

    public func items(
        query: String? = nil,
        category: ClipCategory? = nil,
        smartTag: SmartArchiveTag? = nil
    ) throws -> [ClipItem] {
        try synced {
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var clauses: [String] = []
            var params: [SQLiteValue] = []

            if !trimmed.isEmpty {
                let tokens = trimmed
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                    .filter { !$0.isEmpty }
                for token in tokens {
                    let pattern = "%" + escapeLike(token) + "%"
                    clauses.append(
                        "(body LIKE ? ESCAPE '\\' OR IFNULL(title, '') LIKE ? ESCAPE '\\' OR IFNULL(trigger_code, '') LIKE ? ESCAPE '\\' OR IFNULL(source_app, '') LIKE ? ESCAPE '\\')"
                    )
                    params.append(.text(pattern))
                    params.append(.text(pattern))
                    params.append(.text(pattern))
                    params.append(.text(pattern))
                }
            }

            if let category, let clause = Self.categoryClause(category) {
                clauses.append(clause)
            }

            if let smartTag {
                clauses.append("smart_tag = ?")
                params.append(.text(smartTag.rawValue))
            }

            let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
            SELECT \(Self.columns)
            FROM items
            \(whereSQL)
            ORDER BY
                CASE
                    WHEN is_pinned = 1 THEN 0
                    WHEN kind = 'snippet' THEN 1
                    ELSE 2
                END ASC,
                updated_at DESC,
                id DESC
            """
            return try database.query(sql, params).map(Self.decodeItem)
        }
    }

    public func categoryCounts(query: String? = nil) throws -> [ClipCategory: Int] {
        let all = try items(query: query)
        return all.reduce(into: [:]) { counts, item in
            counts[item.category, default: 0] += 1
        }
    }

    private static func categoryClause(_ category: ClipCategory) -> String? {
        switch category {
        case .image: return "content_type = 'image'"
        case .snippet: return "kind = 'snippet'"
        case .link: return "kind = 'history' AND content_type = 'link'"
        case .text: return "kind = 'history' AND content_type = 'text'"
        }
    }

    private func checkpoint() throws {
        try database.execute("PRAGMA wal_checkpoint(PASSIVE)")
    }

    private func exists(id: Int64) throws -> Bool {
        let rows = try database.query("SELECT 1 FROM items WHERE id = ?", [.int(id)])
        return !rows.isEmpty
    }

    private func itemByID(_ id: Int64) throws -> ClipItem {
        guard let item = try fetchOne(
            "SELECT \(Self.columns) FROM items WHERE id = ?",
            [.int(id)]
        ) else {
            throw StoreError.notFound
        }
        return item
    }

    private func fetchOne(_ sql: String, _ params: [SQLiteValue]) throws -> ClipItem? {
        try database.query(sql, params).first.map(Self.decodeItem)
    }

    private func synced<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func escapeLike(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func decodeItem(_ row: [SQLiteValue]) throws -> ClipItem {
        guard
            row.count >= 13,
            case .int(let id) = row[0],
            case .text(let kindRaw) = row[1],
            let kind = ItemKind(rawValue: kindRaw),
            case .text(let typeRaw) = row[2],
            case .text(let body) = row[3],
            case .int(let pinned) = row[5],
            case .double(let created) = row[6],
            case .double(let updated) = row[7]
        else {
            throw StoreError.executeFailed("unexpected row shape")
        }

        let contentType = ContentType(rawValue: typeRaw) ?? .text

        let title: String?
        if case .text(let value) = row[4] { title = value } else { title = nil }

        let imageData: Data?
        if case .blob(let data) = row[8] { imageData = data } else { imageData = nil }

        let useCount: Int
        if case .int(let count) = row[9] { useCount = Int(count) } else { useCount = 0 }

        let sourceApp: String?
        if case .text(let app) = row[10] { sourceApp = app } else { sourceApp = nil }

        let smartTag: SmartArchiveTag
        if case .text(let tagRaw) = row[11], let parsed = SmartArchiveTag(rawValue: tagRaw) {
            smartTag = parsed
        } else {
            smartTag = .general
        }

        let triggerCode: String?
        if case .text(let code) = row[12] { triggerCode = code } else { triggerCode = nil }

        return ClipItem(
            id: id,
            kind: kind,
            contentType: contentType,
            body: body,
            title: title,
            isPinned: pinned != 0,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            imageData: imageData,
            useCount: useCount,
            sourceApp: sourceApp,
            smartTag: smartTag,
            triggerCode: triggerCode
        )
    }
}
