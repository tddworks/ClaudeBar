import CSQLite
import Foundation
import Quotas

/// The one SQLite (pinned in `Vendor/CSQLite`, #570): a query against
/// another app's own database, read and never written, for the key lookup
/// and the fetch (ENGINE_DESIGN §2.9). The database is opened read-only and a
/// statement that would change it is refused before it runs. Each column
/// comes back as text: TEXT as it is, a BLOB as the UTF-8 or UTF-16LE text an
/// app stored in it.
enum ReadOnlyQuery {
    /// At most this many rows and bytes per value, so an unexpected table
    /// can't flood a mapping.
    static let rowLimit = 1_000
    static let valueLimit = 1_048_576

    /// The rows `query` reads from the database at `path`. `name` is how the
    /// database is called in a failure.
    static func rows(at path: String, query: String, name: String) throws -> [[String: String]] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw UsageError.executionFailed("Couldn't open \(name)")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.executionFailed("Couldn't query \(name)")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) != 0 else {
            throw UsageError.executionFailed("ClaudeBar may only read \(name)")
        }
        var rows: [[String: String]] = []
        while rows.count < rowLimit {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw UsageError.executionFailed("Couldn't query \(name)") }
            rows.append(row(statement))
        }
        return rows
    }

    private static func row(_ statement: OpaquePointer?) -> [String: String] {
        var row: [String: String] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let type = sqlite3_column_type(statement, index)
            let size = Int(sqlite3_column_bytes(statement, index))
            guard type != SQLITE_NULL, size <= valueLimit, let name = sqlite3_column_name(statement, index) else { continue }
            let value: String?
            if type == SQLITE_BLOB {
                value = sqlite3_column_blob(statement, index).map { text(Data(bytes: $0, count: size)) } ?? ""
            } else {
                value = sqlite3_column_text(statement, index).map { String(cString: $0) }
            }
            if let value { row[String(cString: name)] = value }
        }
        return row
    }

    /// The text an app stored as bytes: UTF-8, or UTF-16LE when every other
    /// byte of it is a zero, as plain text in UTF-16 is.
    private static func text(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let looksUTF16 = bytes.count >= 2 && bytes.count % 2 == 0 && stride(from: 1, to: bytes.count, by: 2).contains { bytes[$0] == 0 }
        if looksUTF16, let text = String(data: data, encoding: .utf16LittleEndian) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
