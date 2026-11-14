import Foundation
import CSQLite

enum SQLValue { case text(String), int(Int), double(Double), null }

final class SQLiteConnection {
    private var db: OpaquePointer?
    init(path: String) throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开词库"
            if let db { sqlite3_close(db) }; db = nil
            throw LibraryError.database(message)
        }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
    }
    deinit { if let db { sqlite3_close(db) } }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw error() }
    }

    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                if let pointer = sqlite3_column_text(statement, column) {
                    row[String(cString: sqlite3_column_name(statement, column))] = String(cString: pointer)
                }
            }
            result.append(row); code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw error() }
        return result
    }

    func scalar(_ sql: String, _ values: [SQLValue] = []) throws -> Int {
        Int(try rows(sql, values).first?.values.first ?? "0") ?? 0
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        return try finishTransaction(body)
    }
    func readTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        return try finishTransaction(body)
    }
    private func finishTransaction<T>(_ body: () throws -> T) throws -> T {
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .text(let string): code = sqlite3_bind_text(statement, index, string, -1, transient)
            case .int(let int): code = sqlite3_bind_int64(statement, index, Int64(int))
            case .double(let double): code = sqlite3_bind_double(statement, index, double)
            case .null: code = sqlite3_bind_null(statement, index)
            }
            if code != SQLITE_OK { sqlite3_finalize(statement); throw error() }
        }
        return statement
    }
    private func error() -> LibraryError { .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "词库连接已关闭") }
}
