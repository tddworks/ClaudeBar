import CSQLite
import Foundation

/// A database another app keeps, made by the test with the one SQLite (#570),
/// so a test that reads one runs on every platform, with no `sqlite3` to run.
enum SQLiteFiles {
    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Runs `sql` against the database at `url`, made with its folder if needed.
    static func make(at url: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard url.withUnsafeFileSystemRepresentation({ sqlite3_open($0, &database) }) == SQLITE_OK else {
            throw Failure(description: "couldn't open \(url.lastPathComponent)")
        }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            defer { sqlite3_free(message) }
            throw Failure(description: message.map { String(cString: $0) } ?? "couldn't run the SQL")
        }
    }
}
