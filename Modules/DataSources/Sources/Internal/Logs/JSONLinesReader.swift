import Crypto
import Foundation

/// `jsonLines` — one JSON object per line, in files a tool appends to.
///
/// Keeps the records read from each file between scans, so a scan reads only
/// what changed: nothing for an untouched file, the appended lines for a
/// growing one, and the whole file otherwise.
///
/// Appending is inferred from file metadata plus a hash of the bytes around
/// the already-read prefix; it is not proven. Anything that fails these checks
/// (a new inode, a shrink, coarse timestamps, changed head or tail bytes) is
/// read again from the start.
///
/// With a `kept` file, what it read also outlives the process: a new process
/// (an app relaunched, an hourly uploader started afresh) starts from the file,
/// so a log it was given before is read only from where the last process
/// stopped. The file is checked the same way the memory is, and holds what the
/// last scan kept, nothing older; one that can't be read is read past.
///
/// An actor, so overlapping scans run one after another and the later one
/// finds the earlier one's work already kept.
actor JSONLinesReader {
    /// What the last scan did with each file it was given.
    struct ScanSummary: Equatable, Sendable {
        var reused = 0
        var extended = 0
        var reparsed = 0
    }

    /// Records read from part of a file: the complete lines from the starting
    /// offset onward, and any final line still missing its newline.
    struct Chunk: Sendable, Equatable {
        /// Records from lines that end in a newline.
        let records: [LogRecord]
        /// Byte offset just past the last complete line; the next read resumes here.
        let endOffset: UInt64
        /// Records from a final line with no newline yet. The tool may still be
        /// writing it, so the next read parses it again instead of resuming inside it.
        let tail: [LogRecord]
    }

    private struct Entry: Codable {
        let stamp: FileStamp
        let endOffset: UInt64
        let prefixGuard: Data
        let records: [LogRecord]
        let tail: [LogRecord]
    }

    /// What a `kept` file holds: the entries by path, under the version of
    /// this layout, so a file of another one is read past.
    private struct Kept: Codable {
        static let version = 1
        let version: Int
        let entries: [String: Entry]
    }

    private static let guardBytes: UInt64 = 64 * 1024
    /// A kept file no scan has written for this long is deleted: one a
    /// changed definition, price file or zone left behind, or an idle log's,
    /// which only costs it one full read.
    static let keptFor: TimeInterval = 7 * 24 * 3600
    private static let readChunkSize = 1 << 20
    private static let newline = UInt8(ascii: "\n")

    private let glob: String
    private let shapes: [RecordShape]
    /// A line must hold one of these before it is decoded; `nil` reads every line.
    private let fragments: [[UInt8]]?
    /// By the file's path, as kept on disk too.
    private var entries: [String: Entry] = [:]
    private(set) var lastScan = ScanSummary()
    /// Where what was read is kept between processes; `nil` keeps it in memory only.
    private let kept: URL?
    private var readKept = false
    private var prunedKept = false

    var cachedFileCount: Int { entries.count }

    init(glob: String, shapes: [RecordShape], kept: URL? = nil) {
        self.glob = glob
        self.shapes = shapes
        self.kept = kept
        fragments = shapes.fragments
    }

    /// Records from the files this log names that changed since `since`, in file
    /// order and line order within each file. Files no longer named are forgotten;
    /// unreadable ones are skipped.
    func records(since: Date) -> [LogRecord] {
        records(in: LogFileFinder.files(matching: glob, changedSince: since))
    }

    /// Records from `files`, in file order and line order within each file.
    /// Files not in `files` are forgotten; unreadable ones are skipped.
    func records(in files: [URL]) -> [LogRecord] {
        if !readKept {
            readKept = true
            if entries.isEmpty, let saved = loadKept() { entries = saved }
        }
        var summary = ScanSummary()
        var kept: [String: Entry] = [:]
        var records: [LogRecord] = []
        for url in files {
            guard let entry = refreshedEntry(for: url, summary: &summary) else { continue }
            kept[url.path] = entry
            records.append(contentsOf: entry.records)
            records.append(contentsOf: entry.tail)
        }
        let changed = summary.extended + summary.reparsed > 0 || Set(kept.keys) != Set(entries.keys)
        entries = kept
        lastScan = summary
        if changed { saveKept() }
        return records
    }

    // MARK: - Kept between processes

    private func loadKept() -> [String: Entry]? {
        guard let kept, let data = FileManager.default.contents(atPath: kept.path),
              let saved = try? JSONDecoder().decode(Kept.self, from: data), saved.version == Kept.version
        else { return nil }
        return saved.entries
    }

    /// Writes what this scan kept, whole and at once, so another process
    /// reading meanwhile finds the old file or the new one. A file that can't
    /// be written is left as it was; this process still has its memory.
    private func saveKept() {
        guard let kept else { return }
        let saved = Kept(version: Kept.version, entries: entries)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        let folder = kept.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: kept, options: .atomic)
        if !prunedKept {
            prunedKept = true
            Self.prune(folder, sparing: kept)
        }
    }

    /// Deletes the folder's kept files older than `keptFor`, once a process.
    private static func prune(_ folder: URL, sparing kept: URL) {
        let cutoff = Date().addingTimeInterval(-keptFor)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != kept.lastPathComponent {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Reading a file

    /// Reads a file from `offset` to its end, streaming it rather than loading it whole.
    nonisolated func read(_ url: URL, from offset: UInt64) throws -> Chunk {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var records: [LogRecord] = []
        var endOffset = offset
        var pending = Data()
        while let data = try handle.read(upToCount: Self.readChunkSize), !data.isEmpty {
            // `pending` holds no newline before this read, so only the new bytes need searching.
            let searchFrom = pending.count
            pending.append(data)
            let consumed = scanCompleteLines(in: pending, searchingFrom: searchFrom, into: &records)
            endOffset += UInt64(consumed)
            pending.removeSubrange(pending.startIndex..<pending.startIndex + consumed)
        }
        return Chunk(records: records, endOffset: endOffset, tail: parseTail(pending))
    }

    /// Records in `content`, every line, the last one with or without its newline.
    nonisolated func read(content: String) -> [LogRecord] {
        let data = Data(content.utf8)
        var records: [LogRecord] = []
        let consumed = scanCompleteLines(in: data, searchingFrom: 0, into: &records)
        return records + parseTail(data.dropFirst(consumed))
    }

    /// Appends a record for each newline-terminated line in `data` and returns
    /// how many bytes those lines span. The first newline is searched for from
    /// `searchFrom`, which callers set past bytes already known to hold none.
    private nonisolated func scanCompleteLines(in data: Data, searchingFrom searchFrom: Int, into records: inout [LogRecord]) -> Int {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var lineStart = 0
            var searchStart = searchFrom
            while searchStart < buffer.count,
                  let found = memchr(base + searchStart, Int32(Self.newline), buffer.count - searchStart) {
                let lineEnd = UnsafeRawPointer(found) - base
                if let record = parseLine(UnsafeRawBufferPointer(rebasing: buffer[lineStart..<lineEnd])) {
                    records.append(record)
                }
                lineStart = lineEnd + 1
                searchStart = lineStart
            }
            return lineStart
        }
    }

    private nonisolated func parseTail(_ data: Data) -> [LogRecord] {
        data.withUnsafeBytes { parseLine($0) }.map { [$0] } ?? []
    }

    /// The record on one line, or `nil` when it holds none of the shapes'
    /// fragments, isn't JSON, or isn't a record.
    private nonisolated func parseLine(_ line: UnsafeRawBufferPointer) -> LogRecord? {
        guard let base = line.baseAddress,
              fragments?.contains(where: { ByteSearch.contains($0, in: line) }) ?? true,
              let json = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count))
        else { return nil }
        return shapes.record(from: json)
    }

    // MARK: - Keeping what was read

    private func refreshedEntry(for url: URL, summary: inout ScanSummary) -> Entry? {
        // Stamp first: lines written while reading then show up as a change next scan.
        guard let stamp = FileStamp(url: url) else { return nil }

        if let previous = entries[url.path], previous.stamp.isStrong, stamp.isStrong,
           previous.stamp.inode == stamp.inode {
            if previous.stamp == stamp {
                summary.reused += 1
                return previous
            }
            if stamp.size > previous.stamp.size,
               prefixGuard(of: url, length: previous.endOffset) == previous.prefixGuard,
               let chunk = try? read(url, from: previous.endOffset),
               let guardHash = prefixGuard(of: url, length: chunk.endOffset) {
                summary.extended += 1
                return Entry(stamp: stamp, endOffset: chunk.endOffset, prefixGuard: guardHash,
                             records: previous.records + chunk.records, tail: chunk.tail)
            }
        }

        guard let chunk = try? read(url, from: 0),
              let guardHash = prefixGuard(of: url, length: chunk.endOffset)
        else { return nil }
        summary.reparsed += 1
        return Entry(stamp: stamp, endOffset: chunk.endOffset, prefixGuard: guardHash, records: chunk.records, tail: chunk.tail)
    }

    /// SHA-256 of the first and last `guardBytes` of the file's first `length`
    /// bytes. A bounded spot check, not a proof: it catches truncate-and-rewrite
    /// and changed edges, but not a same-length edit in the middle of a prefix
    /// over 128 KB, which the append-only assumption above rules out. A digest
    /// rather than `Hasher`, whose seed is the process's, so a guard kept in
    /// one process still matches in the next.
    private func prefixGuard(of url: URL, length: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        withUnsafeBytes(of: length.littleEndian) { hash.update(bufferPointer: $0) }
        let headLength = min(length, Self.guardBytes)
        let tailStart = max(headLength, length - min(length, Self.guardBytes))
        do {
            hash.update(data: try handle.read(upToCount: Int(headLength)) ?? Data())
            try handle.seek(toOffset: tailStart)
            hash.update(data: try handle.read(upToCount: Int(length - tailStart)) ?? Data())
        } catch {
            return nil
        }
        return Data(hash.finalize())
    }
}

/// File metadata that changes whenever the file's content does. Each
/// platform reads it its own way (`FileStamp+macOS`, `FileStamp+Windows`).
struct FileStamp: Equatable, Sendable, Codable {
    let inode: UInt64
    let size: UInt64
    let modifiedNanos: Int64
    let changedNanos: Int64

    /// Whether the stamp can tell two versions of a file apart. A filesystem
    /// that keeps whole-second times could change a file twice with an
    /// identical stamp.
    var isStrong: Bool {
        inode != 0 && changedNanos % 1_000_000_000 != 0
    }
}
