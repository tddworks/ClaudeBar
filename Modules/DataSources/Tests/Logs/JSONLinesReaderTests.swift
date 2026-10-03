import Foundation
import Testing
@testable import DataSources

/// `jsonLines`: one record per matching line, read incrementally — only what
/// was appended since the last scan, the whole file when it changed under us.
@Suite
struct JSONLinesReaderTests {
    static let shape = RecordShape(UsageLog.Records(
        files: "~/logs/*.jsonl",
        where: Match(path: "$.kind", equals: .string("reply")),
        at: "$.at",
        id: ["$.reply.id", "$.request"],
        model: "$.reply.model",
        tokens: UsageLog.Tokens(input: "$.reply.usage.in", output: "$.reply.usage.out",
                                cacheWrite: "$.reply.usage.cacheIn", cacheRead: "$.reply.usage.cacheHit")
    ))

    static func line(_ model: String, id: String = UUID().uuidString, at: String = "2026-03-11T10:00:00.000Z") -> String {
        #"{"kind":"reply","request":"q_\#(id)","reply":{"id":"r_\#(id)","model":"\#(model)","usage":{"in":10,"out":5}},"at":"\#(at)"}"#
    }

    private func reader() -> JSONLinesReader { JSONLinesReader(shape: Self.shape) }

    private func makeFile(_ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ content: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
    }

    /// Replaces the file's bytes while keeping its inode, the way an in-place rewrite would.
    private func overwriteInPlace(_ content: String, at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(content.utf8))
    }

    // MARK: - A line

    @Test func `reads a matching line's fields`() {
        let line = #"{"kind":"reply","request":"q_1","reply":{"id":"r_1","model":"m-large","usage":{"in":100,"out":50,"cacheIn":200,"cacheHit":30}},"at":"2026-03-11T10:30:45.123Z"}"#
        let records = reader().read(content: line)
        #expect(records.count == 1)
        #expect(records[0].model == "m-large")
        #expect([records[0].input, records[0].output, records[0].cacheWrite, records[0].cacheRead] == [100, 50, 200, 30] as [Int])
        #expect(records[0].tokens == 150)
        #expect(records[0].id == "r_1\u{1F}q_1")
        #expect(records[0].at == ISO8601Instant.parse("2026-03-11T10:30:45.123Z"))
    }

    @Test func `skips lines that don't match`() {
        let content = """
        {"kind":"ask","reply":{"content":"hello"},"at":"2026-03-11T10:00:00.000Z"}
        \(Self.line("m-large"))
        {"kind":"progress","data":{"kind":"hook"},"at":"2026-03-11T10:00:02.000Z"}
        """
        #expect(reader().read(content: content).map(\.model) == ["m-large"])
    }

    @Test func `a missing token kind counts zero`() {
        let records = reader().read(content: Self.line("m-large"))
        #expect(records[0].cacheWrite == 0)
        #expect(records[0].cacheRead == 0)
    }

    @Test func `a record that says nothing about usage is skipped`() {
        let bare = #"{"kind":"reply","reply":{"model":"m-large"},"at":"2026-03-11T10:00:00.000Z"}"#
        #expect(reader().read(content: bare).isEmpty)
    }

    @Test func `a record without a time or a declared model is skipped`() {
        let noTime = #"{"kind":"reply","reply":{"model":"m-large","usage":{"in":1}}}"#
        let noModel = #"{"kind":"reply","reply":{"usage":{"in":1}},"at":"2026-03-11T10:00:00.000Z"}"#
        #expect(reader().read(content: noTime + "\n" + noModel).isEmpty)
    }

    @Test func `malformed lines are skipped`() {
        let content = "not json at all\n\(Self.line("m-large"))\n{\"incomplete\": true"
        #expect(reader().read(content: content).count == 1)
    }

    @Test func `a record missing an identity part has no identity`() {
        let line = #"{"kind":"reply","reply":{"model":"m-large","usage":{"in":10}},"at":"2026-03-11T10:00:00.000Z"}"#
        #expect(reader().read(content: line).first?.id == nil)
    }

    @Test func `the filter's text inside a quoted string never matches`() {
        let content = #"""
        {"kind":"ask","reply":{"content":"the \"reply\" kind"},"at":"2026-03-11T10:00:00.000Z"}
        """#
        #expect(reader().read(content: content).isEmpty)
    }

    // MARK: - A file, from an offset

    @Test func `reads from a byte offset up to the last complete line`() throws {
        let first = Self.line("m-small")
        let second = Self.line("m-large")
        let unterminated = Self.line("m-tiny")
        let url = try makeFile("\(first)\n\(second)\n\(unterminated)")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let chunk = try reader().read(url, from: UInt64(first.utf8.count + 1))

        #expect(chunk.records.map(\.model) == ["m-large"])
        #expect(chunk.endOffset == UInt64(first.utf8.count + second.utf8.count + 2))
        // The unterminated line still counts, but is left for the next read to finish.
        #expect(chunk.tail.map(\.model) == ["m-tiny"])
    }

    @Test func `reads a line longer than one read`() throws {
        let padding = String(repeating: "x", count: 3 * 1024 * 1024)
        let long = #"{"kind":"reply","reply":{"model":"m-large","content":"\#(padding)","usage":{"in":1,"out":1}},"at":"2026-03-11T10:00:00.000Z"}"#
        let short = Self.line("m-small")
        let url = try makeFile("\(long)\n\(short)\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let chunk = try reader().read(url, from: 0)

        #expect(chunk.records.map(\.model) == ["m-large", "m-small"])
        #expect(chunk.tail.isEmpty)
    }

    // MARK: - Between scans

    @Test func `reuses an unchanged file without reading it again`() async throws {
        let url = try makeFile(Self.line("m-large") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        _ = await reader.records(in: [url])
        let records = await reader.records(in: [url])

        #expect(records.map(\.model) == ["m-large"])
        #expect(await reader.lastScan == JSONLinesReader.ScanSummary(reused: 1, extended: 0, reparsed: 0))
    }

    @Test func `reads only the lines appended since the last scan`() async throws {
        let url = try makeFile(Self.line("m-large") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        _ = await reader.records(in: [url])
        try append(Self.line("m-small") + "\n", to: url)
        let records = await reader.records(in: [url])

        #expect(records.map(\.model) == ["m-large", "m-small"])
        #expect(await reader.lastScan == JSONLinesReader.ScanSummary(reused: 0, extended: 1, reparsed: 0))
    }

    @Test func `finishes a line that was half written at the last scan`() async throws {
        let small = Self.line("m-small")
        let splitAt = small.index(small.startIndex, offsetBy: 40)
        let url = try makeFile(Self.line("m-large") + "\n" + String(small[..<splitAt]))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        let before = await reader.records(in: [url])
        try append(String(small[splitAt...]) + "\n", to: url)
        let after = await reader.records(in: [url])

        #expect(before.map(\.model) == ["m-large"])
        #expect(after.map(\.model) == ["m-large", "m-small"])
    }

    @Test func `counts a complete unterminated last line once after more is appended`() async throws {
        // Records without an identity are never deduplicated later, so a tail
        // line counted twice would inflate the totals.
        let bare = #"{"kind":"reply","reply":{"model":"m-small","usage":{"in":10,"out":5}},"at":"2026-03-11T10:00:00.000Z"}"#
        let url = try makeFile(Self.line("m-large") + "\n" + bare)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        let before = await reader.records(in: [url])
        try append("\n" + Self.line("m-tiny") + "\n", to: url)
        let after = await reader.records(in: [url])

        #expect(before.map(\.model) == ["m-large", "m-small"])
        #expect(after.map(\.model) == ["m-large", "m-small", "m-tiny"])
    }

    @Test func `reads again a file rewritten in place`() async throws {
        let url = try makeFile(Self.line("m-large") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        _ = await reader.records(in: [url])
        try overwriteInPlace(Self.line("m-small") + "\n" + Self.line("m-tiny") + "\n", at: url)
        let records = await reader.records(in: [url])

        #expect(records.map(\.model) == ["m-small", "m-tiny"])
        #expect(await reader.lastScan == JSONLinesReader.ScanSummary(reused: 0, extended: 0, reparsed: 1))
    }

    @Test func `reads again a file that shrank`() async throws {
        let url = try makeFile(Self.line("m-large") + "\n" + Self.line("m-small") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        _ = await reader.records(in: [url])
        try overwriteInPlace(Self.line("m-tiny") + "\n", at: url)

        #expect(await reader.records(in: [url]).map(\.model) == ["m-tiny"])
    }

    @Test func `reads again a file replaced by a new one`() async throws {
        let url = try makeFile(Self.line("m-large") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = reader()

        _ = await reader.records(in: [url])
        // An atomic write lands as a new file (new inode) at the same path.
        try (Self.line("m-large") + "\n" + Self.line("m-small") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let records = await reader.records(in: [url])

        #expect(records.map(\.model) == ["m-large", "m-small"])
        #expect(await reader.lastScan == JSONLinesReader.ScanSummary(reused: 0, extended: 0, reparsed: 1))
    }

    @Test func `forgets files that leave the scan`() async throws {
        let kept = try makeFile(Self.line("m-large") + "\n")
        let dropped = try makeFile(Self.line("m-small") + "\n")
        defer {
            try? FileManager.default.removeItem(at: kept.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: dropped.deletingLastPathComponent())
        }
        let reader = reader()

        _ = await reader.records(in: [kept, dropped])
        let records = await reader.records(in: [kept])

        #expect(records.map(\.model) == ["m-large"])
        #expect(await reader.cachedFileCount == 1)
    }
}
