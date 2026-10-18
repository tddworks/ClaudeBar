import Foundation
import Domain

/// Reads a Claude Code session's titles from its JSONL transcript.
///
/// Claude Code appends `{"type":"custom-title","customTitle":…}` when the
/// session is renamed and `{"type":"ai-title","aiTitle":…}` for its own title,
/// and re-appends both as the session goes on; the latest of each counts.
/// The reader remembers where it stopped in each transcript and reads only the
/// complete lines appended since, so a long session is read once, then in
/// small steps.
public actor TranscriptTitleReader: SessionTitles {
    private struct Progress {
        /// Where the next read starts: just past the last complete line.
        var offset: UInt64 = 0
        var titles = TranscriptTitles(named: nil, generated: nil)
    }

    private static let chunkSize = 1 << 20
    private static let newline = UInt8(ascii: "\n")
    private static let namedMarker = Data(#""custom-title""#.utf8)
    private static let generatedMarker = Data(#""ai-title""#.utf8)

    private var progress: [String: Progress] = [:]

    /// A reader that has read no transcript yet.
    public init() {}

    /// The latest name and Claude Code title in the transcript at `path`,
    /// reading only the complete lines appended since the last read of it.
    /// Both nil when the transcript has neither or can't be opened.
    public func read(transcriptAt path: String) -> TranscriptTitles {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            progress[path] = nil
            return TranscriptTitles(named: nil, generated: nil)
        }
        defer { try? handle.close() }

        var current = progress[path] ?? Progress()
        // A transcript shorter than where we stopped was rewritten: start over.
        if let size = try? handle.seekToEnd(), size < current.offset {
            current = Progress()
        }
        guard (try? handle.seek(toOffset: current.offset)) != nil else { return current.titles }

        var pending = Data()
        while let chunk = try? handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            pending.append(chunk)
            guard let lastNewline = pending.lastIndex(of: Self.newline) else { continue }
            let complete = pending[pending.startIndex...lastNewline]
            for line in complete.split(separator: Self.newline) {
                Self.scan(line, into: &current.titles)
            }
            current.offset += UInt64(complete.count)
            pending = Data(pending[pending.index(after: lastNewline)...])
        }

        progress[path] = current
        return current.titles
    }

    /// Takes the title from a line that holds one; any other line is skipped
    /// without being decoded.
    private static func scan(_ line: Data, into titles: inout TranscriptTitles) {
        guard line.firstRange(of: namedMarker) != nil || line.firstRange(of: generatedMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

        switch json["type"] as? String {
        case "custom-title":
            if let name = nonEmpty(json["customTitle"]) {
                titles = TranscriptTitles(named: name, generated: titles.generated)
            }
        case "ai-title":
            if let title = nonEmpty(json["aiTitle"]) {
                titles = TranscriptTitles(named: titles.named, generated: title)
            }
        default:
            break
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
