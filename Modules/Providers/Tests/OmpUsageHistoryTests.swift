import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Oh My Pi's usage history as data: `omp.json`'s `usageHistory`, read from
/// the session transcripts omp writes under `~/.omp/agent/sessions` — an
/// assistant turn per model reply, and a `model_usage` entry per model call
/// made outside the conversation.
@MainActor
@Suite
struct OmpUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private var sessions: URL { home.appendingPathComponent(".omp/agent/sessions") }

    private func history(environment: @escaping @Sendable (String) -> String? = { _ in nil }) throws -> UsageHistory {
        let definition = try #require(try ProviderFactory.builtIn("omp").usageHistory)
        return UsageHistory(log: DataSources.makeUsageLog(definition, scripts: ProviderFactory.builtInScripts,
                                                          environment: environment, homeDirectory: home))
    }

    private func report(environment: @escaping @Sendable (String) -> String? = { _ in nil }) async throws -> DailyUsageReport {
        let history = try history(environment: environment)
        await history.read()
        return try #require(history.report)
    }

    /// A transcript at `path` under the sessions folder: `<project>/<session>.jsonl`
    /// for a main session, one folder deeper for a subagent's or the advisor's.
    private func write(_ lines: [String], to path: String = "-work-app/2026-10-06T08-00-00-000Z_main.jsonl",
                       in folder: URL? = nil) throws {
        let url = (folder ?? sessions).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var yesterdayNoon: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(43_200)
    }

    private static func entryId() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    private static func usage(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, cost: String) -> String {
        let total = input + output + cacheRead + cacheWrite
        return #"{"input":\#(input),"output":\#(output),"cacheRead":\#(cacheRead),"cacheWrite":\#(cacheWrite),"totalTokens":\#(total),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\#(cost)}}"#
    }

    /// An assistant turn, as omp writes it.
    private static func turn(id: String = entryId(), at: Date = Date(), input: Int, output: Int,
                             cacheRead: Int = 0, cacheWrite: Int = 0, cost: String = "0") -> String {
        let usage = usage(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, cost: cost)
        let millis = Int(at.timeIntervalSince1970 * 1000)
        return #"{"type":"message","id":"\#(id)","parentId":null,"timestamp":"\#(stamp(at))","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":\#(usage),"stopReason":"stop","timestamp":\#(millis)}}"#
    }

    /// A model call omp makes outside the conversation — here its memory's.
    private static func sideCall(at: Date = Date(), input: Int, output: Int, cacheWrite: Int = 0, cost: String = "0") -> String {
        let usage = usage(input: input, output: output, cacheRead: 0, cacheWrite: cacheWrite, cost: cost)
        return #"{"type":"model_usage","id":"\#(entryId())","parentId":null,"timestamp":"\#(stamp(at))","purpose":"memory","role":"memory","api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":\#(usage),"stopReason":"stop"}"#
    }

    private static func ask(_ text: String) -> String {
        #"{"type":"message","id":"\#(entryId())","parentId":null,"timestamp":"\#(stamp(Date()))","message":{"role":"user","content":"\#(text)"}}"#
    }

    /// The `task` tool's result: `details.usage` is the sum of its subagent's turns.
    private static func taskResult(input: Int, output: Int) -> String {
        let usage = usage(input: input, output: output, cacheRead: 0, cacheWrite: 0, cost: "0")
        return #"{"type":"message","id":"\#(entryId())","parentId":null,"timestamp":"\#(stamp(Date()))","message":{"role":"toolResult","toolCallId":"call_1","toolName":"task","content":[{"type":"text","text":"done"}],"details":{"usage":\#(usage)}}}"#
    }

    // MARK: - Turns

    @Test func `should count each turn's tokens today, cache reads and writes apart from input`() async throws {
        try write([
            Self.ask("refactor the parser"),
            Self.turn(input: 2, output: 357, cacheRead: 66_582, cacheWrite: 10_228),
            Self.turn(input: 10, output: 20, cacheRead: 100)
        ])

        let today = try await report().today

        #expect(today.inputTokens == 12)
        #expect(today.outputTokens == 377)
        #expect(today.cacheReadTokens == 66_682)
        #expect(today.cacheCreationTokens == 10_228)
        #expect(today.totalTokens == 389)
    }

    @Test func `should count yesterday's turns as yesterday's`() async throws {
        try write([
            Self.turn(at: Self.yesterdayNoon, input: 100, output: 10),
            Self.turn(input: 200, output: 20)
        ])

        let report = try await report()

        #expect(report.previous.totalTokens == 110)
        #expect(report.today.totalTokens == 220)
    }

    @Test func `should show the cost omp recorded for each call`() async throws {
        try write([
            Self.turn(input: 100, output: 10, cost: "0.25"),
            Self.sideCall(input: 5, output: 1, cost: "0.125")
        ])

        #expect(try history().knowsCost)
        #expect(try await report().today.totalCost == Decimal(string: "0.375"))
    }

    // MARK: - Which entries count

    @Test func `should count the model calls omp makes outside the conversation`() async throws {
        try write([
            Self.turn(input: 100, output: 10),
            Self.sideCall(input: 507, output: 321, cacheWrite: 616)
        ])

        let today = try await report().today

        #expect(today.inputTokens == 607)
        #expect(today.outputTokens == 331)
        #expect(today.cacheCreationTokens == 616)
    }

    @Test func `should count subagent and advisor transcripts beside the main session`() async throws {
        let session = "-work-app/2026-10-06T08-00-00-000Z_main"
        try write([Self.turn(input: 1, output: 1)], to: "\(session).jsonl")
        try write([Self.turn(input: 10, output: 10)], to: "\(session)/Explorer.jsonl")
        try write([Self.turn(input: 100, output: 100)], to: "\(session)/__advisor.jsonl")
        try write([Self.turn(input: 1000, output: 1000)], to: "\(session)/Explorer/Reviewer.jsonl")

        #expect(try await report().today.totalTokens == 2222)
    }

    @Test func `should not count a task's summed usage, which its subagent's transcript already counts`() async throws {
        let session = "-work-app/2026-10-06T08-00-00-000Z_main"
        try write([Self.turn(input: 1, output: 1), Self.taskResult(input: 40, output: 2)], to: "\(session).jsonl")
        try write([Self.turn(input: 40, output: 2)], to: "\(session)/Explorer.jsonl")

        #expect(try await report().today.totalTokens == 44)
    }

    // MARK: - Copies

    @Test func `should count a turn once when a forked session copies it`() async throws {
        let turn = Self.turn(input: 1000, output: 50)
        try write([turn], to: "-work-app/2026-10-06T08-00-00-000Z_parent.jsonl")
        try write([turn, Self.turn(input: 10, output: 5)], to: "-work-app/2026-10-06T09-00-00-000Z_fork.jsonl")

        #expect(try await report().today.totalTokens == 1065)
    }

    @Test func `should count two turns that share an entry id at different times`() async throws {
        try write([Self.turn(id: "1a2b3c4d", input: 1000, output: 50)], to: "-work-app/a.jsonl")
        try write([Self.turn(id: "1a2b3c4d", at: Date().addingTimeInterval(-1), input: 10, output: 5)],
                  to: "-work-other/b.jsonl")

        #expect(try await report().today.totalTokens == 1065)
    }

    // MARK: - Where

    @Test func `should read the sessions of the agent folder PI_CODING_AGENT_DIR names`() async throws {
        let agent = home.appendingPathComponent("custom-agent")
        try write([Self.turn(input: 30, output: 3)], in: agent.appendingPathComponent("sessions"))

        let path = agent.path
        let today = try await report(environment: { $0 == "PI_CODING_AGENT_DIR" ? path : nil }).today

        #expect(today.totalTokens == 33)
    }

    @Test func `should give Oh My Pi's login a usage history its tokens can be shared from`() throws {
        let provider = try ProviderFactory.make("omp", settings: InMemoryProviderSettings())

        #expect(provider.defaultAccount.usageHistory != nil)
    }
}
