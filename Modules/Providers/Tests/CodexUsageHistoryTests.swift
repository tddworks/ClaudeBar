import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Codex's usage history as data: `codex.json`'s `usageHistory`, read from
/// the session logs Codex writes, one `token_count` line per turn.
@MainActor
@Suite
struct CodexUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func history() throws -> UsageHistory {
        let definition = try #require(try Providers.builtIn("codex").usageHistory)
        return UsageHistory(log: DataSources.makeUsageLog(definition, scripts: Providers.builtInScripts,
                                                          environment: { _ in nil }, homeDirectory: home))
    }

    private func report() async throws -> DailyUsageReport {
        let history = try history()
        await history.read()
        return try #require(history.report)
    }

    private func write(_ jsonl: String, to name: String = "rollout-2026-10-04T08-00-00-test.jsonl") throws {
        let dir = home.appendingPathComponent(".codex/sessions/2026/10/04")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try jsonl.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func stamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var yesterdayNoon: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(43_200)
    }

    /// A turn: `last` is this turn's usage, `total` the session's running sum.
    private static func turn(input: Int, cached: Int, output: Int, totalInput: Int, totalOutput: Int,
                             at: Date = Date()) -> String {
        let last = #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(input + output)}"#
        let total = #"{"input_tokens":\#(totalInput),"cached_input_tokens":\#(cached),"output_tokens":\#(totalOutput),"total_tokens":\#(totalInput + totalOutput)}"#
        return #"{"timestamp":"\#(stamp(at))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(total),"last_token_usage":\#(last)}}}"#
    }

    @Test func `today's tokens are each turn's, with cached input counted as cache reads`() async throws {
        try write([
            Self.turn(input: 1000, cached: 600, output: 50, totalInput: 1000, totalOutput: 50),
            Self.turn(input: 2000, cached: 1500, output: 80, totalInput: 3000, totalOutput: 130)
        ].joined(separator: "\n"))

        let today = try await report().today

        #expect(today.inputTokens == 900)        // (1000 − 600) + (2000 − 1500)
        #expect(today.cacheReadTokens == 2100)
        #expect(today.outputTokens == 130)
        #expect(today.totalTokens == 1030)
    }

    @Test func `a turn written twice counts once`() async throws {
        let turn = Self.turn(input: 1000, cached: 0, output: 50, totalInput: 1000, totalOutput: 50)
        try write([turn, turn].joined(separator: "\n"))

        #expect(try await report().today.totalTokens == 1050)
    }

    @Test func `lines without usage and other events are skipped`() async throws {
        try write([
            #"{"timestamp":"\#(Self.stamp())","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
            #"{"timestamp":"\#(Self.stamp())","type":"turn_context","payload":{"model":"gpt-x"}}"#,
            Self.turn(input: 100, cached: 0, output: 10, totalInput: 100, totalOutput: 10)
        ].joined(separator: "\n"))

        #expect(try await report().today.totalTokens == 110)
    }

    @Test func `yesterday's turns land on yesterday`() async throws {
        try write([
            Self.turn(input: 100, cached: 0, output: 10, totalInput: 100, totalOutput: 10, at: Self.yesterdayNoon),
            Self.turn(input: 200, cached: 0, output: 20, totalInput: 300, totalOutput: 30)
        ].joined(separator: "\n"))

        let report = try await report()

        #expect(report.previous.totalTokens == 110)
        #expect(report.today.totalTokens == 220)
    }

    @Test func `Codex's logs name no model, so its history has no cost to show`() throws {
        #expect(try !history().knowsCost)
        let claude = try #require(try Providers.builtIn("claude").usageHistory)
        #expect(UsageHistory(log: DataSources.makeUsageLog(claude, scripts: Providers.builtInScripts,
                                                           environment: { _ in nil }, homeDirectory: home)).knowsCost)
    }

    @Test func `an added account reads its own Codex folder`() throws {
        let definition = try Providers.builtIn("codex")
        let account = try #require(definition.usageHistory(forAccount: ["codexHome": "/tmp/work-codex"]))
        #expect(account.records.files == "/tmp/work-codex/sessions/**/rollout-*.jsonl")
    }
}
