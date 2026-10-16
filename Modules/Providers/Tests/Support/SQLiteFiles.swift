import CSQLite
import Foundation

/// A database another app keeps, made and queried by the test with the one
/// SQLite (#570), so a test that reads one runs on every platform, with no
/// `sqlite3` to run.
enum SQLiteFiles {
    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Runs `sql` against the database at `url`, made with its folder if needed.
    static func make(at url: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try open(url) { database in
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
                defer { sqlite3_free(message) }
                throw Failure(description: message.map { String(cString: $0) } ?? "couldn't run the SQL")
            }
        }
    }

    /// The rows `query` reads, each column as `sqlite3 -json` gives it: an
    /// integer or a real as a number, text as text, `NULL` left out.
    static func rows(at url: URL, _ query: String) throws -> [[String: Any]] {
        try open(url) { database in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                throw Failure(description: String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            var rows: [[String: Any]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: row[name] = NSNumber(value: sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT: row[name] = NSNumber(value: sqlite3_column_double(statement, index))
                    case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, index))
                    default: break
                    }
                }
                rows.append(row)
            }
            return rows
        }
    }

    private static func open<T>(_ url: URL, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard url.withUnsafeFileSystemRepresentation({ sqlite3_open($0, &database) }) == SQLITE_OK else {
            throw Failure(description: "couldn't open \(url.lastPathComponent)")
        }
        return try body(database)
    }
}
