import Foundation
import SQLite3

enum SQLiteValue: Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK, handle != nil else {
            throw StoreError.openFailed(errorMessage())
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, _ params: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, params)
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw StoreError.executeFailed(errorMessage())
        }
    }

    func query(_ sql: String, _ params: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, params)
        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw StoreError.executeFailed(errorMessage())
            }
            rows.append(readRow(statement))
        }
        return rows
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.executeFailed(errorMessage())
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ params: [SQLiteValue]) throws {
        for (index, value) in params.enumerated() {
            let slot = Int32(index + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(statement, slot)
            case .int(let number):
                status = sqlite3_bind_int64(statement, slot, number)
            case .double(let number):
                status = sqlite3_bind_double(statement, slot, number)
            case .text(let text):
                status = sqlite3_bind_text(statement, slot, text, -1, SQLITE_TRANSIENT)
            }
            guard status == SQLITE_OK else {
                throw StoreError.executeFailed(errorMessage())
            }
        }
    }

    private func readRow(_ statement: OpaquePointer?) -> [SQLiteValue] {
        let count = sqlite3_column_count(statement)
        return (0..<count).map { column in
            switch sqlite3_column_type(statement, column) {
            case SQLITE_INTEGER:
                return .int(sqlite3_column_int64(statement, column))
            case SQLITE_FLOAT:
                return .double(sqlite3_column_double(statement, column))
            case SQLITE_TEXT:
                if let pointer = sqlite3_column_text(statement, column) {
                    return .text(String(cString: pointer))
                }
                return .null
            default:
                return .null
            }
        }
    }

    private func errorMessage() -> String {
        if let handle {
            return String(cString: sqlite3_errmsg(handle))
        }
        return "unknown sqlite error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
