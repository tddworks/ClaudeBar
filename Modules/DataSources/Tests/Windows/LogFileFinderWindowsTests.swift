#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import DataSources

/// Windows lists a log folder from its directory entries, without opening
/// each file for reading: a folder of thousands of session files is listed
/// in a fraction of a second, even when Windows hasn't touched them for a
/// while, and a file another program holds open alone is still found.
@Suite
struct LogFileFinderWindowsTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    @discardableResult
    private func file(_ name: String, _ text: String = "{}\n") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func glob(_ pattern: String) -> String {
        root.path + "/" + pattern
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map { String($0.path.dropFirst(root.path.count + 1)) }
    }

    /// Opens `url` for writing and shares it with no one, as a program that
    /// keeps its log to itself does, until the returned handle is closed.
    private func holdAlone(_ url: URL) throws -> HANDLE {
        let handle = url.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw CocoaError(.fileReadNoPermission) }
        return handle
    }

    @Test
    func `should find a log another program holds open without sharing it`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try file("a/kept.jsonl")
        let held = try file("a/held.jsonl")
        let handle = try holdAlone(held)
        defer { CloseHandle(handle) }

        let found = LogFileFinder.files(matching: glob("**/*.jsonl"), changedSince: .distantPast)

        #expect(names(found) == ["a/held.jsonl", "a/kept.jsonl"])
    }

    @Test
    func `should count a log as changed while its writer still holds it open`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try file("a/session.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 86400)],
                                              ofItemAtPath: url.path)
        // The writer appends and keeps the file open: NTFS leaves the folder's
        // entry for it at the old time and size until the file is closed.
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("{\"more\":1}\n".utf8))

        let found = LogFileFinder.files(matching: glob("**/*.jsonl"), changedSince: Date(timeIntervalSinceNow: -3600))

        #expect(names(found) == ["a/session.jsonl"])
    }

    @Test
    func `should list the logs the glob names at any depth, changed since the date, leaving out hidden files`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try file("top.jsonl")
        try file("a/b/deep.jsonl")
        try file("a/notes.md")
        let old = try file("a/old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 86400)],
                                              ofItemAtPath: old.path)
        let hidden = try file("a/hidden.jsonl")
        _ = hidden.path.withCString(encodedAs: UTF16.self) { SetFileAttributesW($0, DWORD(FILE_ATTRIBUTE_HIDDEN)) }

        let found = LogFileFinder.files(matching: glob("**/*.jsonl"), changedSince: Date(timeIntervalSinceNow: -86400))

        #expect(names(found) == ["a/b/deep.jsonl", "top.jsonl"])
    }

    @Test
    func `should name each log by the same path as before, so what the last scan kept still matches`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try file("a/b/deep.jsonl")

        let found = LogFileFinder.files(matching: glob("**/*.jsonl"), changedSince: .distantPast)
        let resolved = root.resolvingSymlinksInPath()

        #expect(found.map(\.path) == [resolved.appendingPathComponent("a").appendingPathComponent("b")
                                      .appendingPathComponent("deep.jsonl").path])
    }
}
#endif
