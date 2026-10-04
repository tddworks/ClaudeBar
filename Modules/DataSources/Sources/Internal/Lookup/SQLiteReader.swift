import Foundation
import SQLite3

/// `sqlite` — the first row of a read-only query against another app's own
/// database. The database is opened read-only and a statement that would
/// change it is refused, so ClaudeBar never writes, creates or copies it.
struct SQLiteReader: CredentialFinding {
    let file: SQLiteCredential
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    func find() throws -> FoundCredential? {
        let path = Paths.expand(file.path, homeDirectory: homeDirectory, environment: environment)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw UsageError.executionFailed("Couldn't open \(file.path)")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, file.query, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.executionFailed("Couldn't query \(file.path)")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) != 0 else {
            throw UsageError.executionFailed("A key lookup may only read \(file.path)")
        }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw UsageError.executionFailed("Couldn't query \(file.path)") }
        var row: [String: Any] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  sqlite3_column_bytes(statement, index) <= 65_536,
                  let name = sqlite3_column_name(statement, index),
                  let text = sqlite3_column_text(statement, index) else { continue }
            row[String(cString: name)] = String(cString: text)
        }
        let values = CredentialDocument.values(file.fields, in: row)
        guard values["token"] != nil else { return nil }
        return FoundCredential(credential: Credential(values), save: nil)
    }
}
