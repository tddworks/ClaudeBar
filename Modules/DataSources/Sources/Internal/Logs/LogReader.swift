import Foundation

/// The reader for a log's `format` — one per case of the closed list.
enum LogReader: Sendable {
    case jsonLines(JSONLinesReader)
    case json(JSONLogReader)

    init(_ records: UsageLog.Records) {
        switch records.format {
        case .jsonLines: self = .jsonLines(JSONLinesReader(records: records))
        case .json: self = .json(JSONLogReader(records: records))
        }
    }

    /// Records from `files`, in file order.
    func records(in files: [URL]) async -> [LogRecord] {
        switch self {
        case .jsonLines(let reader): await reader.records(in: files)
        case .json(let reader): reader.records(in: files)
        }
    }

    /// What the last scan did — only a reader that keeps files between scans can say.
    var lastScan: JSONLinesReader.ScanSummary {
        get async {
            switch self {
            case .jsonLines(let reader): await reader.lastScan
            case .json: JSONLinesReader.ScanSummary()
            }
        }
    }
}

/// `json` — one JSON document per file, one record each: a session's
/// summary, written whole. Small files, so each scan reads them again. A file
/// is read by the first shape whose `where` holds, as a line is.
struct JSONLogReader: Sendable {
    private let shapes: [RecordShape]

    init(records: UsageLog.Records) {
        shapes = records.shapes.map(RecordShape.init)
    }

    func records(in files: [URL]) -> [LogRecord] {
        files.compactMap { url in
            guard let data = FileManager.default.contents(atPath: url.path),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return shapes.record(from: json, path: url.path)
        }
    }
}
