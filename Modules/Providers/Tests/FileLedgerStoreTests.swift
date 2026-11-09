import Foundation
import Quotas
import Testing
@testable import Providers

/// Kept days on disk: one small JSON file per login, read back exactly.
@Suite
struct FileLedgerStoreTests {
    private let store = FileLedgerStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    @Test func `should read back kept days exactly as they were saved, with money exact`() {
        let day = DailyUsageStat(date: Date(timeIntervalSince1970: 1_759_449_600), totalCost: Decimal(string: "0.0105")!,
                                 totalTokens: 1500, workingTime: 600, sessionCount: 1, inputTokens: 1000, outputTokens: 500,
                                 cachedSavings: Decimal(string: "2.7")!)
        let page = LedgerPage(fingerprint: "f1", days: ["2025-10-03": day])

        store.save(page, for: "claude")

        #expect(store.load("claude") == page)
    }

    @Test func `should have no kept days when nothing was saved or the file is damaged`() throws {
        #expect(store.load("claude") == nil)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try "{".write(to: store.directory.appendingPathComponent("claude.json"), atomically: true, encoding: .utf8)
        #expect(store.load("claude") == nil)
    }

    @Test func `should keep each login's days in its own file`() {
        store.save(LedgerPage(fingerprint: "a", days: [:]), for: "claude")
        store.save(LedgerPage(fingerprint: "b", days: [:]), for: "claude.work")
        #expect(store.load("claude")?.fingerprint == "a")
        #expect(store.load("claude.work")?.fingerprint == "b")
    }

    /// A closed day is read from the logs once and then kept; by the time it
    /// is read again its logs may be gone (Claude Code deletes old sessions),
    /// so a kept day that doesn't reach its file can drop out of the history.
    /// The app starts programs all the time; none of them may keep a save from
    /// the file, or leave a file beside it.
    @Test func `should keep every saved day while the app starts programs`() async throws {
        let store = store
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let lost = try await StartingPrograms.meanwhile { () -> [Int] in
            (0..<300).filter { round in
                let page = LedgerPage(fingerprint: "f\(round)", days: [:])
                store.save(page, for: "claude")
                return store.load("claude") != page
            }
        }

        #expect(lost == [], "saves that didn't reach the file")
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == ["claude.json"])
    }
}
