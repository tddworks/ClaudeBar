import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Mistral's usage history as data: `mistral.json`'s `usageHistory` reads
/// Vibe's session folders — one `meta.json` each, its time in the folder's
/// UTC name — on the old analyzer's fixtures.
@MainActor
@Suite
struct MistralUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func report() async throws -> DailyUsageReport? {
        let definition = try #require(try ProviderFactory.builtIn("mistral").usageHistory)
        let history = UsageHistory(log: DataSources.makeUsageLog(definition, scripts: ProviderFactory.builtInScripts,
                                                                 environment: { _ in nil }, homeDirectory: home))
        await history.read()
        return history.report
    }

    /// A session folder as Vibe names it: `session_YYYYMMDD_HHMMSS_<id>`, in UTC.
    private func session(at date: Date = Date(), id: String = UUID().uuidString.prefix(6).lowercased(),
                         meta: String?) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dir = home.appendingPathComponent(".vibe/logs/session/session_\(formatter.string(from: date))_\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let meta { try meta.write(to: dir.appendingPathComponent("meta.json"), atomically: true, encoding: .utf8) }
    }

    private func meta(tokens: Int, cost: String = "0.00") -> String {
        #"{ "stats": { "session_total_llm_tokens": \#(tokens), "session_cost": \#(cost) } }"#
    }

    @Test func `should sum today's Vibe sessions into today's tokens and session count`() async throws {
        try session(meta: meta(tokens: 1500))
        try session(meta: meta(tokens: 3000))
        let today = try #require(try await report()).today
        #expect(today.totalTokens == 4500)
        #expect(today.sessionCount == 2)
        // A session's own time is not logged, so none is guessed.
        #expect(today.workingTime == 0)
    }

    @Test func `should count yesterday's sessions on yesterday`() async throws {
        try session(meta: meta(tokens: 1500))
        try session(at: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, meta: meta(tokens: 3000))
        let report = try #require(try await report())
        #expect(report.today.totalTokens == 1500)
        #expect(report.previous.totalTokens == 3000)
    }

    @Test func `should show each session's own cost exactly`() async throws {
        try session(meta: meta(tokens: 50_000, cost: "2.40"))
        #expect(try await report()?.today.totalCost == Decimal(string: "2.40"))
    }

    @Test func `should skip a session whose log is broken or incomplete`() async throws {
        try session(meta: meta(tokens: 1500))
        try session(meta: "{ not valid json !! }")
        try session(meta: #"{ "title": "no stats" }"#)
        try session(meta: nil)
        let today = try #require(try await report()).today
        #expect(today.totalTokens == 1500)
        #expect(today.sessionCount == 1)
    }

    @Test func `should show no usage history when Vibe has no sessions`() async throws {
        #expect(try await report() == nil)
    }

    @Test func `should date each session by its folder's name, in UTC`() throws {
        let rule = UsageLog.At.FromPath(pattern: #"session_(\d{8}_\d{6})"#, format: "yyyyMMdd_HHmmss", timeZone: "UTC")
        let definition = try #require(try ProviderFactory.builtIn("mistral").usageHistory)
        #expect(definition.records.shapes.map(\.at) == [.fromPath(rule)])
        #expect(definition.records.format == .json)
    }
}
