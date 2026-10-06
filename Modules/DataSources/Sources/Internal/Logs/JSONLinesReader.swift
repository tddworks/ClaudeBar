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

    private struct Entry {
        let stamp: FileStamp
        let endOffset: UInt64
        let prefixGuard: Int
        let records: [LogRecord]
        let tail: [LogRecord]
    }

    private static let guardBytes: UInt64 = 64 * 1024
    private static let readChunkSize = 1 << 20
    private static let newline = UInt8(ascii: "\n")

    private let shapes: [RecordShape]
    /// A line must hold one of these before it is decoded; `nil` reads every line.
    private let fragments: [[UInt8]]?
    private var entries: [URL: Entry] = [:]
    private(set) var lastScan = ScanSummary()

    var cachedFileCount: Int { entries.count }

    init(records: UsageLog.Records) {
        shapes = records.shapes.map(RecordShape.init)
        fragments = shapes.fragments
    }

    /// Records from `files`, in file order and line order within each file.
    /// Files not in `files` are forgotten; unreadable ones are skipped.
    func records(in files: [URL]) -> [LogRecord] {
        var summary = ScanSummary()
        var kept: [URL: Entry] = [:]
        var records: [LogRecord] = []
        for url in files {
            guard let entry = refreshedEntry(for: url, summary: &summary) else { continue }
            kept[url] = entry
            records.append(contentsOf: entry.records)
            records.append(contentsOf: entry.tail)
        }
        entries = kept
        lastScan = summary
        return records
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
              fragments?.contains(where: { fragment in memmem(base, line.count, fragment, fragment.count) != nil }) ?? true,
              let json = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count))
        else { return nil }
        return shapes.record(from: json)
    }

    // MARK: - Keeping what was read

    private func refreshedEntry(for url: URL, summary: inout ScanSummary) -> Entry? {
        // Stamp first: lines written while reading then show up as a change next scan.
        guard let stamp = FileStamp(url: url) else { return nil }

        if let previous = entries[url], previous.stamp.isStrong, stamp.isStrong,
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

    /// Hash of the first and last `guardBytes` of the file's first `length`
    /// bytes. A bounded spot check, not a proof: it catches truncate-and-rewrite
    /// and changed edges, but not a same-length edit in the middle of a prefix
    /// over 128 KB, which the append-only assumption above rules out.
    private func prefixGuard(of url: URL, length: UInt64) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Hasher()
        hasher.combine(length)
        let headLength = min(length, Self.guardBytes)
        let tailStart = max(headLength, length - min(length, Self.guardBytes))
        do {
            hasher.combine(try handle.read(upToCount: Int(headLength)) ?? Data())
            try handle.seek(toOffset: tailStart)
            hasher.combine(try handle.read(upToCount: Int(length - tailStart)) ?? Data())
        } catch {
            return nil
        }
        return hasher.finalize()
    }
}

/// File metadata that changes whenever the file's content does.
struct FileStamp: Equatable, Sendable {
    let inode: UInt64
    let size: UInt64
    let modifiedNanos: Int64
    let changedNanos: Int64

    init?(url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = UInt64(info.st_size)
        modifiedNanos = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        changedNanos = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
    }

    /// Whether the stamp can tell two versions of a file apart. A filesystem
    /// that keeps whole-second times could change a file twice with an
    /// identical stamp.
    var isStrong: Bool {
        inode != 0 && changedNanos % 1_000_000_000 != 0
    }
}
