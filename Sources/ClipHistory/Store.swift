import Foundation

public final class Store: @unchecked Sendable {
    private let database: Database
    private let lock = NSLock()

    public init(path: String) throws {
        database = try Database(path: path)
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                body TEXT NOT NULL,
                title TEXT,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_kind_updated ON items(kind, updated_at DESC)"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_body_kind ON items(body, kind)"
        )
    }

    @discardableResult
    public func recordHistory(_ body: String, now: Date = Date()) throws -> ClipItem {
        try synced {
            if let existing = try fetchOne(
                """
                SELECT id, kind, body, title, is_pinned, created_at, updated_at
                FROM items
                WHERE kind = ? AND body = ?
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

            try database.execute(
                """
                INSERT INTO items (kind, body, title, is_pinned, created_at, updated_at)
                VALUES (?, ?, NULL, 0, ?, ?)
                """,
                [
                    .text(ItemKind.history.rawValue),
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

    @discardableResult
    public func addSnippet(title: String?, body: String, now: Date = Date()) throws -> ClipItem {
        try synced {
            try database.execute(
                """
                INSERT INTO items (kind, body, title, is_pinned, created_at, updated_at)
                VALUES (?, ?, ?, 0, ?, ?)
                """,
                [
                    .text(ItemKind.snippet.rawValue),
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

    public func items(query: String? = nil) throws -> [ClipItem] {
        try synced {
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sql: String
            let params: [SQLiteValue]
            if trimmed.isEmpty {
                sql = """
                SELECT id, kind, body, title, is_pinned, created_at, updated_at
                FROM items
                ORDER BY
                    CASE
                        WHEN is_pinned = 1 THEN 0
                        WHEN kind = 'snippet' THEN 1
                        ELSE 2
                    END ASC,
                    updated_at DESC,
                    id DESC
                """
                params = []
            } else {
                let pattern = "%" + escapeLike(trimmed) + "%"
                sql = """
                SELECT id, kind, body, title, is_pinned, created_at, updated_at
                FROM items
                WHERE body LIKE ? ESCAPE '\\'
                   OR IFNULL(title, '') LIKE ? ESCAPE '\\'
                ORDER BY
                    CASE
                        WHEN is_pinned = 1 THEN 0
                        WHEN kind = 'snippet' THEN 1
                        ELSE 2
                    END ASC,
                    updated_at DESC,
                    id DESC
                """
                params = [.text(pattern), .text(pattern)]
            }
            return try database.query(sql, params).map(Self.decodeItem)
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
            """
            SELECT id, kind, body, title, is_pinned, created_at, updated_at
            FROM items
            WHERE id = ?
            """,
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
            row.count >= 7,
            case .int(let id) = row[0],
            case .text(let kindRaw) = row[1],
            let kind = ItemKind(rawValue: kindRaw),
            case .text(let body) = row[2],
            case .int(let pinned) = row[4],
            case .double(let created) = row[5],
            case .double(let updated) = row[6]
        else {
            throw StoreError.executeFailed("unexpected row shape")
        }

        let title: String?
        switch row[3] {
        case .text(let value):
            title = value
        case .null:
            title = nil
        default:
            title = nil
        }

        return ClipItem(
            id: id,
            kind: kind,
            body: body,
            title: title,
            isPinned: pinned != 0,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }
}
