import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite
struct TranscriptTitleReaderTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("TranscriptTitleReaderTests-\(UUID().uuidString)")

    private func transcript(_ lines: [String]) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private static let prompt = #"{"type":"user","message":{"role":"user","content":"pull the latest main"}}"#
    private static func named(_ title: String) -> String { #"{"type":"custom-title","customTitle":"\#(title)","sessionId":"s"}"# }
    private static func generated(_ title: String) -> String { #"{"type":"ai-title","aiTitle":"\#(title)","sessionId":"s"}"# }

    @Test
    func `should find the latest name and Claude Code title`() async throws {
        let url = try transcript([
            Self.prompt,
            Self.generated("Pull latest main"),
            Self.named("First name"),
            Self.prompt,
            Self.named("Session names"),
        ])

        let titles = await TranscriptTitleReader().read(transcriptAt: url.path)

        #expect(titles == TranscriptTitles(named: "Session names", generated: "Pull latest main"))
    }

    @Test
    func `should find a title appended after the last read`() async throws {
        let url = try transcript([Self.prompt, Self.generated("Pull latest main")])
        let reader = TranscriptTitleReader()
        _ = await reader.read(transcriptAt: url.path)

        try append([Self.prompt, Self.named("Session names")], to: url)
        let titles = await reader.read(transcriptAt: url.path)

        #expect(titles == TranscriptTitles(named: "Session names", generated: "Pull latest main"))
    }

    @Test
    func `should keep the titles when nothing was appended`() async throws {
        let url = try transcript([Self.named("Session names")])
        let reader = TranscriptTitleReader()
        _ = await reader.read(transcriptAt: url.path)

        let titles = await reader.read(transcriptAt: url.path)

        #expect(titles.named == "Session names")
    }

    @Test
    func `should find a title whose line was still being written at the last read`() async throws {
        let url = try transcript([Self.prompt])
        let reader = TranscriptTitleReader()
        let line = Self.named("Session names")
        let half = line.index(line.startIndex, offsetBy: line.count / 2)
        try append([String(line[..<half])], to: url)
        // `append` ends every write with a newline; strip it so the line is cut mid-way.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: try handle.seekToEnd() - 1)
        try handle.close()
        _ = await reader.read(transcriptAt: url.path)

        try append([String(line[half...])], to: url)
        let titles = await reader.read(transcriptAt: url.path)

        #expect(titles.named == "Session names")
    }

    @Test
    func `should read a transcript again from the start once it was rewritten shorter`() async throws {
        let url = try transcript([Self.prompt, Self.prompt, Self.named("First name")])
        let reader = TranscriptTitleReader()
        _ = await reader.read(transcriptAt: url.path)

        try (Self.named("Session names") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let titles = await reader.read(transcriptAt: url.path)

        #expect(titles.named == "Session names")
    }

    @Test
    func `should keep a name when a later one is blank`() async throws {
        let url = try transcript([Self.named("Session names"), Self.named("  ")])

        let titles = await TranscriptTitleReader().read(transcriptAt: url.path)

        #expect(titles.named == "Session names")
    }

    @Test
    func `should have no titles for a transcript that doesn't exist`() async {
        let titles = await TranscriptTitleReader().read(transcriptAt: "/nonexistent/\(UUID().uuidString).jsonl")

        #expect(titles == TranscriptTitles(named: nil, generated: nil))
    }
}
