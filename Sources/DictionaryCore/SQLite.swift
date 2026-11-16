import Foundation
import CSQLite

enum SQLValue { case text(String), int(Int), double(Double), null }

final class SQLiteConnection {
    private var db: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]
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
    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        if let db { sqlite3_close(db) }
    }

    private func recycle(_ statement: OpaquePointer, for sql: String) {
        sqlite3_reset(statement); sqlite3_clear_bindings(statement)
        if statements.count < 64, statements[sql] == nil { statements[sql] = statement }
        else { sqlite3_finalize(statement) }
    }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values); defer { recycle(statement, for: sql) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw error() }
    }

    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[String: String]] {
        var result: [[String: String]] = []
        try forEachRow(sql, values) { result.append($0) }
        return result
    }

    func forEachRow(_ sql: String, _ values: [SQLValue] = [], _ body: ([String: String]) throws -> Void) throws {
        let statement = try prepare(sql, values); defer { recycle(statement, for: sql) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                if let pointer = sqlite3_column_text(statement, column) {
                    row[String(cString: sqlite3_column_name(statement, column))] = String(cString: pointer)
                }
            }
            try body(row); code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw error() }
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
        var prepared = statements.removeValue(forKey: sql)
        if prepared == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK else { throw error() }
        }
        guard let statement = prepared else { throw error() }
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
