import Diagnostics
import Foundation

/// `sqlite` — one fixed, read-only call on an app's own database, each row
/// of the answer one record: the app's records without its CLI in between
/// (`opencode db "<sql>" --format json` was this, until the subcommand went).
/// The call picks its query as every `sqlite` fetch does — the first whose
/// tables the store has — and runs it through `ReadOnlyQuery`, so opening
/// read-only and refusing a write are written once. A database that is not
/// there, or one none of its queries fits, is an empty read, as an
/// unreadable file is; a query that fails is logged as one.
struct SQLiteLogReader: Sendable {
    private let call: SQLiteCall
    private let shapes: [RecordShape]
    private let homeDirectory: URL
    private let environment: @Sendable (String) -> String?

    init(call: SQLiteCall, shapes: [RecordShape],
         homeDirectory: URL, environment: @escaping @Sendable (String) -> String?) {
        self.call = call
        self.shapes = shapes
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    /// `since` is the reader's, not the query's: a query answers whatever it
    /// holds, and the range asked for is cut from it by `days(in:)`. A query
    /// that bounded itself below the range asked would have its older days
    /// read as empty — and kept that way by the ledger. Every row is read: a
    /// fetch's cap spares a script, and these records go to the aggregator.
    func records(since: Date) -> [LogRecord] {
        let path = Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
        guard FileManager.default.fileExists(atPath: path) else {
            AppLog.probes.info("Usage history: no database at \(call.path), so the log reads empty")
            return []
        }
        do {
            guard let query = try call.query(at: path) else {
                AppLog.probes.info("Usage history: \(call.path) has none of the tables its queries read, so the log reads empty")
                return []
            }
            let answer = try ReadOnlyQuery.rows(at: path, query: query, name: call.path.description, limit: nil)
            return answer.compactMap { shapes.record(from: Self.asWritten($0)) }
        } catch {
            AppLog.probes.warning("Usage history: the query of \(call.path) failed (\(error.localizedDescription)), so the log reads empty")
            return []
        }
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
