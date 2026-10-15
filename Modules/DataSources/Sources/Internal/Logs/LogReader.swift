import Foundation

/// The reader for a log's source — one per case of the closed list. Each one
/// is told what to read and never asked what it holds: a file reader finds
/// its own files, the command reader runs its command, and nothing above
/// branches on which kind of log it has.
enum LogReader: Sendable {
    case jsonLines(JSONLinesReader)
    case json(JSONLogReader)
    case command(CommandLogReader)

    /// - Parameter expand: the caller's path language — `~` and
    ///   `${VAR:-default}` — resolved the way the platform's paths are.
    init(_ records: UsageLog.Records, expand: (String) -> String, platform: Platform, homeDirectory: URL,
         environment: @escaping @Sendable (String) -> String?) {
        let shapes = records.shapes.map(RecordShape.init)
        switch records.source {
        case .files(let glob, let format):
            switch format {
            case .jsonLines: self = .jsonLines(JSONLinesReader(glob: expand(glob), shapes: shapes))
            case .json: self = .json(JSONLogReader(glob: expand(glob), shapes: shapes))
            }
        case .command(let call):
            self = .command(CommandLogReader(fetcher: platform.runCommand.map {
                CommandFetcher(call: call, makeExecutor: $0,
                               directory: { call.workingDirectory.map { _ in
                                   DataSources.cliWorkingDirectory(platform: platform, homeDirectory: homeDirectory,
                                                                  environment: environment)
                               } })
            }, shapes: shapes))
        }
    }

    /// Every record this log holds from `since` on, oldest source order first.
    func records(since: Date) async -> [LogRecord] {
        switch self {
        case .jsonLines(let reader): await reader.records(since: since)
        case .json(let reader): reader.records(since: since)
        case .command(let reader): await reader.records(since: since)
        }
    }

    /// What the last scan did — only a reader that keeps files between scans
    /// can say, and the others say nothing rather than an empty scan.
    var scan: JSONLinesReader.ScanSummary? {
        get async {
            switch self {
            case .jsonLines(let reader): await reader.lastScan
            case .json, .command: nil
            }
        }
    }
}

/// `json` — one JSON document per file, one record each: a session's
/// summary, written whole. Small files, so each scan reads them again. A file
/// is read by the first shape whose `where` holds, as a line is.
struct JSONLogReader: Sendable {
    private let glob: String
    private let shapes: [RecordShape]

    init(glob: String, shapes: [RecordShape]) {
        self.glob = glob
        self.shapes = shapes
    }

    func records(since: Date) -> [LogRecord] {
        LogFileFinder.files(matching: glob, changedSince: since).compactMap { url in
            guard let data = FileManager.default.contents(atPath: url.path),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return shapes.record(from: json, path: url.path)
        }
    }
}
