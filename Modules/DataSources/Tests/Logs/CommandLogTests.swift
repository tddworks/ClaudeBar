import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// A usage log read from one fixed command's JSON answer — a tool whose
/// records live in a database it can query itself (`opencode db … --format
/// json`). The answer is one JSON array, each element a record.
@Suite
struct CommandLogTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = Calendar.current
    private let now = Date()

    private static let call = CommandCall(cli: "acme", args: ["db", "SELECT tokens FROM message", "--format", "json"], timeout: 15)

    private static let definition = UsageLog.Definition(
        records: UsageLog.Records(
            command: Self.call,
            shapes: [UsageLog.Shape(at: "$.at", id: ["$.id"],
                                    tokens: UsageLog.Tokens(input: "$.in", output: "$.out", cacheRead: "$.cacheRead"),
                                    cost: "$.cost")]
        ),
        sessionGap: 1800
    )

    private func cli(output: String, exit: Int32 = 0, installed: Bool = true) -> MockCLIExecutor {
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(installed ? "/test/acme" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: output, exitCode: exit))
        return cli
    }

    /// A platform that runs `executor` for the log's command — the one way a
    /// login's log is built, so a test needs no seam of its own.
    private func platform(running executor: (any CLIExecutor)?) -> Platform {
        var platform = Platform.current
        if let executor {
            platform.runCommand = { _ in executor }
        } else {
            platform.runCommand = nil
        }
        return platform
    }

    private func log(_ definition: UsageLog.Definition = Self.definition,
                     _ executor: (any CLIExecutor)?) -> UsageLog {
        DataSources.makeUsageLog(definition, platform: platform(running: executor), scripts: { _ in nil },
                                 environment: { _ in nil }, homeDirectory: home, calendar: calendar,
                                 now: { [now] in now })
    }

    /// Where the command was asked to run, read once the log has read.
    private final class Where: @unchecked Sendable { var directory: URL? }

    private func row(id: String, at: Int, input: Int, output: Int, cost: Double) -> String {
        #"{"id":"\#(id)","at":\#(at),"in":\#(input),"out":\#(output),"cacheRead":0,"cost":\#(cost)}"#
    }

    @Test func `should read one record a row of the command's JSON answer`() async throws {
        let epoch = Int(now.timeIntervalSince1970)
        let output = "[\(row(id: "a", at: epoch, input: 1000, output: 500, cost: 0.01))]"
        let days = await log(Self.definition, cli(output: output)).days(last: 1)
        #expect(days[0].totalTokens == 1500)
        #expect(days[0].totalCost == Decimal(string: "0.01"))
    }

    @Test func `should count usage on the day it happened, a row older than the range dropped`() async throws {
        let today = Int(now.timeIntervalSince1970)
        let yesterday = Int(now.addingTimeInterval(-86_400).timeIntervalSince1970)
        let older = Int(now.addingTimeInterval(-40 * 86_400).timeIntervalSince1970)
        let output = """
        [\(row(id: "a", at: today, input: 1000, output: 500, cost: 0)), \
        \(row(id: "b", at: yesterday, input: 2000, output: 1000, cost: 0)), \
        \(row(id: "c", at: older, input: 4000, output: 2000, cost: 0))]
        """
        // The command answers everything it holds; the range asked for is cut
        // here, so a wider answer never widens the answer's days.
        let days = await log(Self.definition, cli(output: output)).days(last: 2)
        #expect(days.count == 2)
        #expect(days[1].totalTokens == 1500)
        #expect(days[0].totalTokens == 3000)
    }

    @Test func `should show every day empty when the CLI is missing, fails, or prints nothing readable`() async throws {
        for output in [cli(output: ""), cli(output: "not json", installed: false), cli(output: "{}"), cli(output: "[{}]", exit: 1)] {
            #expect(await log(Self.definition, output).days(last: 1)[0].isEmpty)
        }
    }

    @Test func `should show every day empty when the command cannot start`() async throws {
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn("/test/acme")
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(UsageError.cliNotFound("acme"))
        #expect(await log(Self.definition, cli).days(last: 1)[0].isEmpty)
    }

    @Test func `should show every day empty on a platform that runs no commands`() async throws {
        #expect(await log(Self.definition, nil).days(last: 1)[0].isEmpty)
    }

    @Test func `should run a command that asks for ClaudeBar's own folder in that folder`() async throws {
        let ran = Where()
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn("/test/acme")
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, _, _, _, directory, _ in
                ran.directory = directory
                return CLIResult(output: "[]", exitCode: 0)
            }
        let definition = UsageLog.Definition(
            records: UsageLog.Records(
                command: CommandCall(cli: "acme", args: ["db", "SELECT tokens FROM message", "--format", "json"],
                                     timeout: 15, workingDirectory: .dedicated),
                shapes: Self.definition.records.shapes))
        _ = await log(definition, cli).days(last: 1)
        #expect(ran.directory == DataSources.cliWorkingDirectory(platform: .current, homeDirectory: home,
                                                                environment: { _ in nil }))
    }

    @Test func `should count rows whose shape answers and skip the rest`() async throws {
        let epoch = Int(now.timeIntervalSince1970)
        let output = #"[{"id":"a","at":\#(epoch),"in":1000,"out":500}, {"kind":"user","at":\#(epoch)}, {"id":"c"}]"#
        #expect(await log(Self.definition, cli(output: output)).days(last: 1)[0].totalTokens == 1500)
    }

    // MARK: - The definition

    @Test func `should refuse a log that gives files and a command together, or neither`() {
        let both = #"{"records": { "files": "~/x/*.jsonl", "command": {"cli": "acme"}, "at": "$.at", "tokens": {"total": "$.n"} }}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UsageLog.Definition.self, from: Data(both.utf8)) }
        let neither = #"{"records": { "at": "$.at", "tokens": {"total": "$.n"} }}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UsageLog.Definition.self, from: Data(neither.utf8)) }
    }

    @Test func `should keep a command log when written out and read back`() throws {
        let again = try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(Self.definition))
        #expect(again == Self.definition)
        #expect(again.records.source == .command(Self.call))
    }

    @Test func `should fingerprint two different commands apart, so days kept under one are not reused for the other`() {
        let other = UsageLog.Definition(
            records: UsageLog.Records(
                command: CommandCall(cli: "acme", args: ["db", "SELECT other FROM message", "--format", "json"], timeout: 15),
                shapes: Self.definition.records.shapes),
            sessionGap: 1800)
        #expect(log(other, cli(output: "[]")).fingerprint != log(Self.definition, cli(output: "[]")).fingerprint)
    }
}
