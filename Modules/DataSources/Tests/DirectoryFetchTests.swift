import Foundation
import Quotas
import Testing
@testable import DataSources

/// A folder some tool fills with its logs: ready while it exists, answered
/// with the names in it that match.
@Suite
struct DirectoryFetchTests {
    private func folder(_ names: [String]) throws -> (URL, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logs = home.appendingPathComponent(".acme/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for name in names { try FileManager.default.createDirectory(at: logs.appendingPathComponent(name), withIntermediateDirectories: true) }
        return (home, { try? FileManager.default.removeItem(at: home) })
    }

    @Test func `the matching entries come back, in order`() async throws {
        let (home, cleanUp) = try folder(["session_2", "session_1", "other"])
        defer { cleanUp() }
        let fetcher = DirectoryFetcher(call: DirectoryCall(path: "~/.acme/logs", match: "^session_"), homeDirectory: home, environment: { _ in nil })
        #expect(fetcher.isReady())
        let body = try #require(try JSONSerialization.jsonObject(with: try await fetcher.fetch(with: nil).body) as? [String: Any])
        #expect(body["entries"] as? [String] == ["session_1", "session_2"])
    }

    @Test func `a folder that isn't there isn't ready`() throws {
        let fetcher = DirectoryFetcher(call: DirectoryCall(path: "~/.nowhere"), homeDirectory: FileManager.default.temporaryDirectory, environment: { _ in nil })
        #expect(!fetcher.isReady())
    }

    @Test func `it round-trips as written`() throws {
        let fetch = Fetch.directory(DirectoryCall(path: "~/.acme/logs", match: "^session_"))
        #expect(try JSONDecoder().decode(Fetch.self, from: JSONEncoder().encode(fetch)) == fetch)
    }
}
