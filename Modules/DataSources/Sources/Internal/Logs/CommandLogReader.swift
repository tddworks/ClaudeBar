import Diagnostics
import Foundation

/// `command` — one fixed, read-only command whose JSON answer holds the
/// records: a tool whose logs are a database it can query itself (`opencode
/// db "<sql>" --format json`). The answer is one JSON array, each element
/// read by the first shape whose `where` holds.
///
/// The command itself is run by `CommandFetcher`, the same worker every other
/// command fetch uses, so locating it, running it, its exit code, its working
/// directory and a failure to start are written once. A platform that runs no
/// commands holds no fetcher; a command that is missing, fails, or answers
/// something its shapes cannot read is an empty read, as an unreadable file is.
struct CommandLogReader: Sendable {
    private let fetcher: CommandFetcher?
    private let shapes: [RecordShape]

    init(fetcher: CommandFetcher?, shapes: [RecordShape]) {
        self.fetcher = fetcher
        self.shapes = shapes
    }

    /// `since` is the reader's, not the query's: a command answers whatever it
    /// answers, and the range asked for is cut from it by `days(in:)`. A query
    /// that bounded itself below the range asked would have its older days read
    /// as empty — and kept that way by the ledger.
    func records(since: Date) async -> [LogRecord] {
        guard let fetcher else {
            AppLog.probes.info("Usage history: this platform runs no commands, so the log reads empty")
            return []
        }
        guard let answer = try? await fetcher.fetch(with: nil).text,
              let rows = try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [Any] else {
            AppLog.probes.error("Usage history: \(fetcher.call.cli) printed no JSON array, so its log reads empty")
            return []
        }
        return rows.compactMap { shapes.record(from: $0) }
    }
}
