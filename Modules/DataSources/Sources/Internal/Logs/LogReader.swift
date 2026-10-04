import Foundation

/// The reader for a log's `format` — one per case of the closed list.
enum LogReader: Sendable {
    case jsonLines(JSONLinesReader)
    case json(JSONLogReader)

    init(_ records: UsageLog.Records) {
        let shape = RecordShape(records)
        switch records.format {
        case .jsonLines: self = .jsonLines(JSONLinesReader(shape: shape))
        case .json: self = .json(JSONLogReader(shape: shape))
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
/// summary, written whole. Small files, so each scan reads them again.
struct JSONLogReader: Sendable {
    let shape: RecordShape

    func records(in files: [URL]) -> [LogRecord] {
        files.compactMap { url in
            guard let data = FileManager.default.contents(atPath: url.path),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return shape.record(from: json, path: url.path)
        }
    }
}
