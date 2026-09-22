import Foundation

public final class Store: @unchecked Sendable {
    private let database: Database
    private let lock = NSLock()

    /// Canonical column order shared by every SELECT and `decodeItem`.
    private static let columns =
        "id, kind, content_type, body, title, is_pinned, created_at, updated_at, data"

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
                data BLOB
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
    }

    /// Add columns to databases created before content-type / image support and
    /// backfill obvious links so old rows filter correctly.
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
        try database.execute(
            """
            UPDATE items SET content_type = 'link'
            WHERE content_type = 'text'
              AND (lower(body) LIKE 'http://%' OR lower(body) LIKE 'https://%')
            """
        )
    }

    @discardableResult
    public func recordHistory(_ body: String, now: Date = Date()) throws -> ClipItem {
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
                    "UPDATE items SET updated_at = ? WHERE id = ?",
                    [.double(now.timeIntervalSince1970), .int(existing.id)]
                )
                let item = try itemByID(existing.id)
                try checkpoint()
                return item
            }

            let contentType = ContentClassifier.classify(body)
            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at)
                VALUES (?, ?, ?, NULL, 0, ?, ?)
                """,
                [
                    .text(ItemKind.history.rawValue),
                    .text(contentType.rawValue),
                    .text(body),
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970)
                ]
            )
            let item = try itemByID(database.lastInsertRowID)
            try checkpoint()
            return item
        }
    }

    /// Records an image (PNG bytes). Deduplicates by identical bytes, moving an
    /// existing copy to the front instead of inserting a duplicate.
    @discardableResult
    public func recordImage(_ data: Data, width: Int = 0, height: Int = 0, now: Date = Date()) throws -> ClipItem {
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
                    "UPDATE items SET updated_at = ? WHERE id = ?",
                    [.double(now.timeIntervalSince1970), .int(existing.id)]
                )
                let item = try itemByID(existing.id)
                try checkpoint()
                return item
            }

            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at, data)
                VALUES (?, 'image', ?, NULL, 0, ?, ?, ?)
                """,
                [
                    .text(ItemKind.history.rawValue),
                    .text(Self.imageDescriptor(width: width, height: height)),
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970),
                    .blob(data)
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
    public func addSnippet(title: String?, body: String, now: Date = Date()) throws -> ClipItem {
        try synced {
            let contentType = ContentClassifier.classify(body)
            try database.execute(
                """
                INSERT INTO items (kind, content_type, body, title, is_pinned, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, ?, ?)
                """,
                [
                    .text(ItemKind.snippet.rawValue),
                    .text(contentType.rawValue),
                    .text(body),
                    title.map { .text($0) } ?? .null,
                    .double(now.timeIntervalSince1970),
                    .double(now.timeIntervalSince1970)
                ]
            )
            let item = try itemByID(database.lastInsertRowID)
            try checkpoint()
            return item
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

    /// Returns items, newest first (pinned then snippets then history). When
    /// `category` is provided, only items in that category are returned.
    public func items(query: String? = nil, category: ClipCategory? = nil) throws -> [ClipItem] {
        try synced {
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var clauses: [String] = []
            var params: [SQLiteValue] = []

            if !trimmed.isEmpty {
                let pattern = "%" + escapeLike(trimmed) + "%"
                clauses.append("(body LIKE ? ESCAPE '\\' OR IFNULL(title, '') LIKE ? ESCAPE '\\')")
                params.append(.text(pattern))
                params.append(.text(pattern))
            }

            if let category, let clause = Self.categoryClause(category) {
                clauses.append(clause)
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

    /// Count of items per category (honouring an optional search query).
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
            row.count >= 9,
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
        if case .text(let value) = row[4] {
            title = value
        } else {
            title = nil
        }

        let imageData: Data?
        if case .blob(let data) = row[8] {
            imageData = data
        } else {
            imageData = nil
        }

        return ClipItem(
            id: id,
            kind: kind,
            contentType: contentType,
            body: body,
            title: title,
            isPinned: pinned != 0,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            imageData: imageData
        )
    }
}
