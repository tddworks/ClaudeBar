import Diagnostics
import Foundation

/// `sqlite` — one fixed, read-only query of an app's own database, each row
/// of the answer one record: the app's records without its CLI in between
/// (`opencode db "<sql>" --format json` was this, until the subcommand went).
/// The query runs on the platform's SQLite — the same worker every `sqlite`
/// fetch uses, so opening read-only and refusing a write are written once. A
/// platform with no SQLite, a database that is not there, or a query the
/// database cannot answer is an empty read, as an unreadable file is.
struct SQLiteLogReader: Sendable {
    private let call: SQLiteCall
    private let rows: SQLiteRows?
    private let shapes: [RecordShape]
    private let homeDirectory: URL
    private let environment: @Sendable (String) -> String?

    init(call: SQLiteCall, rows: SQLiteRows?, shapes: [RecordShape],
         homeDirectory: URL, environment: @escaping @Sendable (String) -> String?) {
        self.call = call
        self.rows = rows
        self.shapes = shapes
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    /// `since` is the reader's, not the query's: a query answers whatever it
    /// holds, and the range asked for is cut from it by `days(in:)`. A query
    /// that bounded itself below the range asked would have its older days
    /// read as empty — and kept that way by the ledger.
    func records(since: Date) -> [LogRecord] {
        guard let rows else {
            AppLog.probes.info("Usage history: this platform has no SQLite, so the log reads empty")
            return []
        }
        let path = Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
        guard FileManager.default.fileExists(atPath: path),
              let answer = try? rows(path, call.query, call.path.description) else {
            AppLog.probes.info("Usage history: no database at \(call.path), so the log reads empty")
            return []
        }
        return answer.compactMap { shapes.record(from: Self.asWritten($0)) }
    }

    /// Each column as the database wrote it: numbers as numbers, the rest as
    /// text — what the database's own JSON printer would have written, so a
    /// shape reads a row exactly as it reads the same answer from a command.
    private static func asWritten(_ row: [String: String]) -> [String: Any] {
        row.mapValues { value in
            // A database count or cost: a number, whatever the type read back.
            if let number = Double(value), value.trimmingCharacters(in: .whitespaces) == value, !value.isEmpty {
                return NSNumber(value: number)
            }
            return value
        }
    }
}
