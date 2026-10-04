import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Claude's usage history as data: `claude.json`'s `usageHistory` and
/// `claude-prices.json`, run on the old analyzer's fixtures — the same
/// numbers *TODAY'S USAGE* showed before (#190, #207).
@MainActor
@Suite
struct ClaudeUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func history() throws -> UsageHistory {
        let definition = try #require(try Providers.builtIn("claude").usageHistory)
        return UsageHistory(log: DataSources.makeUsageLog(definition, scripts: Providers.builtInScripts,
                                                          environment: { _ in nil }, homeDirectory: home))
    }

    private func report() async throws -> DailyUsageReport {
        let history = try history()
        await history.read()
        return try #require(history.report)
    }

    private func write(_ jsonl: String, to name: String = "test-session.jsonl") throws {
        let dir = home.appendingPathComponent(".claude/projects/test-project")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try jsonl.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// Claude Code's own config, where its route is.
    private func route(_ json: String) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try json.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }

    private static func stamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var yesterdayNoon: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(43_200)
    }

    private static func line(_ model: String = "claude-sonnet-4-6", input: Int = 1000, output: Int = 500, cacheWrite: Int = 0,
                             cacheRead: Int = 0, message: String? = nil, request: String? = nil, at: Date = Date()) -> String {
        let requestId = request.map { #""requestId":"\#($0)","# } ?? ""
        let messageId = message.map { #""id":"\#($0)","# } ?? ""
        return #"{"type":"assistant",\#(requestId)"message":{\#(messageId)"model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead)}},"timestamp":"\#(stamp(at))"}"#
    }

    @Test func `today's usage is read from the session logs`() async throws {
        try write(Self.line())
        let report = try await report()
        #expect(report.today.totalTokens == 1500)
        #expect(report.today.totalCost == Decimal(string: "0.0105"))
        #expect(report.previous.isEmpty)
    }

    @Test func `no logs is no report`() async throws {
        let history = try history()
        await history.read()
        #expect(history.report == nil)
    }

    @Test func `today and yesterday are told apart`() async throws {
        try write([Self.line(), Self.line(input: 2000, output: 1000, at: Self.yesterdayNoon)].joined(separator: "\n"))
        let report = try await report()
        #expect(report.today.totalTokens == 1500)
        #expect(report.previous.totalTokens == 3000)
    }

    @Test func `cache tokens and savings are summed`() async throws {
        try write(Self.line(cacheWrite: 2000, cacheRead: 1_000_000))
        let today = try await report().today
        #expect([today.inputTokens, today.outputTokens, today.cacheCreationTokens, today.cacheReadTokens] == [1000, 500, 2000, 1_000_000] as [Int])
        #expect(today.cachedSavings == Decimal(string: "2.7"))
        #expect(today.cacheHitRate > 0.99)
    }

    // MARK: - Streamed and copied messages count once (#207)

    @Test func `a message repeated across content blocks counts once`() async throws {
        let line = Self.line(message: "msg_A", request: "req_1")
        try write([line, line, line].joined(separator: "\n"))
        #expect(try await report().today.totalTokens == 1500)
    }

    @Test func `the final streamed snapshot wins`() async throws {
        try write([Self.line(output: 1, message: "msg_A", request: "req_1"),
                   Self.line(output: 1, message: "msg_A", request: "req_1", at: Date().addingTimeInterval(0.1)),
                   Self.line(output: 500, message: "msg_A", request: "req_1", at: Date().addingTimeInterval(0.9))].joined(separator: "\n"))
        let today = try await report().today
        #expect(today.outputTokens == 500)
        #expect(today.totalTokens == 1500)
    }

    @Test func `a response copied into a resumed session file counts once`() async throws {
        let line = Self.line(message: "msg_A", request: "req_1")
        try write(line, to: "session-1.jsonl")
        try write(line, to: "session-2.jsonl")
        #expect(try await report().today.totalTokens == 1500)
    }

    @Test func `lines missing an id or request id are all counted`() async throws {
        let line = Self.line()
        try write([line, line].joined(separator: "\n"))
        #expect(try await report().today.totalTokens == 3000)
    }

    // MARK: - Prices from claude-prices.json

    @Test func `models are priced as Anthropic lists them`() async throws {
        // 1M in / 100K out / 1M cache write / 1M cache read each.
        try write([Self.line("claude-sonnet-4-6", input: 1_000_000, output: 100_000, cacheWrite: 1_000_000, cacheRead: 1_000_000, message: "a", request: "1"),
                   Self.line("claude-opus-4-99-20260101", input: 1_000_000, output: 0, message: "b", request: "2"),
                   Self.line("glm-4.6", input: 1_000_000, output: 0, message: "c", request: "3")].joined(separator: "\n"))
        // Sonnet $8.55, an unknown Opus at Opus 4.6's $5 input, a paid gateway's model at the Sonnet estimate $3.
        #expect(try await report().today.totalCost == Decimal(string: "16.55"))
    }

    @Test func `the current models have today's list prices`() async throws {
        try write([Self.line("claude-opus-5-5", input: 1_000_000, output: 100_000, message: "a", request: "1"),
                   Self.line("claude-haiku-4-5-20251001", input: 1_000_000, output: 0, cacheRead: 1_000_000, message: "b", request: "2")]
            .joined(separator: "\n"))
        // Opus 5.5: $4 + $2; Haiku 4.5, dated: $1 + $0.10 of cache reads.
        #expect(try await report().today.totalCost == Decimal(string: "7.1"))
    }

    @Test func `cache writes kept an hour cost the hour price`() async throws {
        let line = #"{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":100000,"ephemeral_1h_input_tokens":900000}}},"timestamp":"\#(Self.stamp())"}"#
        try write(line)
        let today = try await report().today
        // Opus 5.5: 0.1M × $5 + 0.9M × $8 of writes, $0.004 in, $0.01 out.
        #expect(today.totalCost == Decimal(string: "7.714"))
        #expect(today.cacheCreationTokens == 1_000_000)
    }

    // MARK: - Local inference costs nothing (#190)

    @Test func `an open-weight model costs nothing, its cache reads saving nothing`() async throws {
        try write(Self.line("qwen3-coder:30b", cacheRead: 1_000_000))
        let today = try await report().today
        #expect(today.totalCost == 0)
        #expect(today.cachedSavings == 0)
        #expect(today.cacheReadTokens == 1_000_000)
        #expect(today.totalTokens == 1500)
    }

    @Test func `an unpriced model costs nothing when Claude Code is routed at this Mac`() async throws {
        try route(#"{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}"#)
        try write(Self.line("acme-internal-7b", cacheRead: 1_000_000))
        let today = try await report().today
        #expect(today.totalCost == 0)
        #expect(today.cachedSavings == 0)
    }

    @Test func `a local route listed only among providers counts when env names none`() async throws {
        try route(#"{"providers":[{"base_url":"https://api.anthropic.com"},{"env":{"ANTHROPIC_BASE_URL":"http://[::1]:11434"}}]}"#)
        try write(Self.line("some-unknown-model"))
        #expect(try await report().today.totalCost == 0)
    }

    @Test func `a remote route outranks a local provider entry`() async throws {
        try route(#"{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic"},"providers":[{"base_url":"http://localhost:11434"}]}"#)
        try write(Self.line("some-unknown-model"))
        #expect(try await report().today.totalCost == Decimal(string: "0.0105"))
    }

    @Test func `a known Anthropic model keeps its list price on a local route`() async throws {
        try route(#"{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1234"}}"#)
        try write(Self.line())
        #expect(try await report().today.totalCost == Decimal(string: "0.0105"))
    }

    @Test func `yesterday keeps its estimate when the route is local now`() async throws {
        try route(#"{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}"#)
        try write(Self.line("some-unknown-model", at: Self.yesterdayNoon))
        let report = try await report()
        #expect(report.today.isEmpty)
        #expect(report.previous.totalCost == Decimal(string: "0.0105"))
        #expect(report.previous.totalTokens == 1500)
    }

    // MARK: - Each login reads its own folder

    /// Claude with one added login in `work`, every history over `home`.
    private func provider(work: URL) throws -> Provider {
        let definition = try Providers.builtIn("claude")
        let make = { (history: UsageLog.Definition) in
            UsageHistory(log: DataSources.makeUsageLog(history, scripts: Providers.builtInScripts,
                                                       environment: { _ in nil }, homeDirectory: self.home))
        }
        return Provider(
            definition: definition, settings: InMemoryProviderSettings(),
            accounts: [ProviderAccountConfig(accountId: "work", label: "", email: "work@example.com",
                                             probeConfig: ["configDirectory": work.path, "loginEmail": "work@example.com", "credentialService": "fixture-work"])],
            makeDataSource: { source, _ in DataSources.make(source, providerId: "claude") },
            usageHistory: definition.usageHistory.map(make),
            makeUsageHistory: { history, _ in make(history) }
        )
    }

    @Test func `an added login reads its own config folder's logs, never the default's`() async throws {
        let work = home.appendingPathComponent("work-claude")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("projects/p"), withIntermediateDirectories: true)
        try Self.line(input: 2000, output: 1000).write(to: work.appendingPathComponent("projects/p/s.jsonl"), atomically: true, encoding: .utf8)
        try write(Self.line())
        let provider = try provider(work: work)
        let added = try #require(provider.accounts.first { !$0.isDefault })

        await provider.defaultAccount.usageHistory?.read()
        await added.usageHistory?.read()

        #expect(provider.defaultAccount.usageHistory?.report?.today.totalTokens == 1500)
        #expect(added.usageHistory?.report?.today.totalTokens == 3000)
        #expect(added.usageHistory !== provider.defaultAccount.usageHistory)
    }

    @Test func `an added login's local route is its own folder's`() async throws {
        let work = home.appendingPathComponent("work-claude")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("projects/p"), withIntermediateDirectories: true)
        try Self.line("acme-internal-7b").write(to: work.appendingPathComponent("projects/p/s.jsonl"), atomically: true, encoding: .utf8)
        try #"{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}"#.write(to: work.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        let added = try #require(try provider(work: work).accounts.first { !$0.isDefault })

        await added.usageHistory?.read()

        #expect(added.usageHistory?.report?.today.totalCost == 0)
    }

    @Test func `an added login's usage history goes with it`() throws {
        let provider = try provider(work: home.appendingPathComponent("work-claude"))
        let added = try #require(provider.accounts.first { !$0.isDefault })
        #expect(added.usageHistory != nil)

        provider.remove(added)

        #expect(added.usageHistory == nil)
    }

    @Test func `the patch fills the folder into where the logs and the route are`() throws {
        let own = try #require(try Providers.builtIn("claude").usageHistory(forAccount: ["configDirectory": "/tmp/work"]))
        #expect(own.records.files == "/tmp/work/projects/**/*.jsonl")
        #expect(own.freeWhen?.localEndpoint?.file == "/tmp/work/.claude.json")
        #expect(own.freeWhen?.localEndpoint?.url.count == 2)
        #expect(try Providers.builtIn("claude").usageHistory(forAccount: [:]) == nil)
    }
}
