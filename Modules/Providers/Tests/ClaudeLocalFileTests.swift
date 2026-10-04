import DataSources
import Quotas
import Foundation
import Mockable
import Testing
@testable import Providers

/// Claude's `localFile` data source — Claude Desktop's daily token counter
/// at `~/Library/Application Support/Claude/buddy-tokens.json` (issue #198),
/// read by the `file` fetcher and `claude-buddy-tokens.js`. What the old
/// `ClaudeDesktopFileUsageProbe` and `ClaudeProviderLocalFileTests` pinned is
/// pinned here against the definition: the counter becomes a "Tokens Today"
/// note, never a quota; anything unrecognisable is a structural error; a
/// counter that isn't from the user's local day is no data; and the data
/// source neither falls back to CLI/API nor floors the background refresh.
@MainActor
@Suite
struct ClaudeLocalFileTests {

    // MARK: - Fixtures

    /// The local day of `date`, as the script's `context.timeZone` (the
    /// process zone) names it — the string a current buddy-tokens file carries.
    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// A fixed instant — the harness clock every scenario runs on.
    private static let now = Date(timeIntervalSince1970: 1_779_926_400)

    private func buddyTokens(_ date: String, _ tokens: Int) -> String {
        #"{"tokens-today": {"date": "\#(date)", "tokens": \#(tokens)}}"#
    }

    /// Writes the counter file where the `file` fetch looks for it.
    private func writeBuddyTokens(_ harness: ClaudeHarness, contents: String) throws {
        let directory = harness.home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent("buddy-tokens.json"))
    }

    /// The counter file as the data source reads it: fetched off disk, then
    /// mapped by the script. Throws the `UsageError` the step means.
    private func readFromDisk(_ harness: ClaudeHarness) async throws -> UsageSnapshot {
        try await harness.fetchUsage(harness.dataSource("localFile"))
    }

    /// A body mapped by the script alone — no file on disk.
    private func readBody(_ harness: ClaudeHarness, _ body: String) async throws -> UsageSnapshot {
        do {
            return try harness.dataSource("localFile").read(Response(text: body))
        } catch let failure as DataSourceError {
            throw failure.reason
        }
    }

    /// A CLI that is found and would answer a `/usage` screen — every file
    /// scenario runs with it, to prove file mode never asks.
    private func answerCLI(_ harness: ClaudeHarness) {
        given(harness.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(harness.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "Current session\n80% left\nResets in 2h 15m"))
    }

    /// The provider's default login, saved to `localFile` mode.
    private func localFileAccount(_ harness: ClaudeHarness) throws -> Account {
        try harness.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "localFile"]))
    }

    // MARK: - The definition

    @Test
    func `claude has a localFile data source with the buddy-tokens fetch`() throws {
        let definition = try Providers.builtIn("claude")
        let source = try #require(definition.dataSource("localFile"))
        #expect(source.label == "Local File")
        #expect(source.summary == "Reads Claude Desktop's buddy-tokens.json (best-effort)")
        guard case .file(let call) = source.fetch else {
            Issue.record("localFile is not a file data source")
            return
        }
        #expect(call.path == "~/Library/Application Support/Claude/buddy-tokens.json")
        guard case .script(let mapping) = source.mapping else {
            Issue.record("localFile is not mapped by a script")
            return
        }
        #expect(mapping.file == "claude-buddy-tokens.js")
    }

    @Test
    func `localFile neither falls back nor caches`() throws {
        let source = try #require(Providers.builtIn("claude").dataSource("localFile"))
        // A daily token total is not a five-hour window: substituting CLI/API
        // data would present the wrong semantic as the user's chosen data, and
        // a local file read is cheap enough to keep the user's own interval.
        #expect(source.fallback == nil)
        #expect(source.cache == nil)
    }

    @Test
    func `the saved probe mode value names the data source`() throws {
        // ClaudeProbeMode.localFile persists as its raw value under the same
        // key Provider.activeKind reads — the saved value and the definition's
        // kind must keep matching, or the saved choice selects nothing.
        try #expect(Providers.builtIn("claude").dataSource("localFile") != nil)
    }

    // MARK: - The happy path

    @Test
    func `reads today's tokens as a note, not a quota`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        try writeBuddyTokens(harness, contents: buddyTokens(Self.day(Self.now), 74_422))
        let snapshot = try await readFromDisk(harness)

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.capturedAt == Self.now)
        let metric = try #require(snapshot.extensionMetrics?.first)
        #expect(metric.label == "Tokens Today")
        #expect(metric.value == "74,422")
        #expect(metric.group == "Claude Desktop")
    }

    @Test
    func `groups large counts and keeps zero`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        let large = try await readBody(harness, buddyTokens(Self.day(Self.now), 1_204_556))
        #expect(large.extensionMetrics?.first?.value == "1,204,556")

        let zero = try await readBody(harness, buddyTokens(Self.day(Self.now), 0))
        #expect(zero.extensionMetrics?.first?.value == "0")
    }

    // MARK: - Availability

    @Test
    func `a current file is ready and a missing one is not`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        let source = try harness.dataSource("localFile")
        #expect(await source.isReady() == false)

        try writeBuddyTokens(harness, contents: buddyTokens(Self.day(Self.now), 100))
        #expect(await source.isReady() == true)
    }

    @Test
    func `a missing file fails the fetch`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        // The engine answers for the file alone; there is nothing to hand over to.
        await #expect(throws: UsageError.executionFailed("No file at ~/Library/Application Support/Claude/buddy-tokens.json")) {
            try await readFromDisk(harness)
        }
    }

    // MARK: - Schema changes fail gracefully

    @Test
    func `malformed JSON is a parse failure`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        await #expect(throws: UsageError.parseFailed("buddy-tokens.json is not valid JSON")) {
            try await readBody(harness, #"{"tokens-today": {"date":"2026-05-28""#)
        }
    }

    @Test(arguments: [
        (#"{"something-else": {}}"#, "buddy-tokens.json schema changed: missing 'tokens-today'"),
        (#"{"tokens-today": {"date": "2026-05-28"}}"#, "buddy-tokens.json schema changed: missing 'tokens-today.tokens'"),
        (#"{"tokens-today": {"tokens": 100}}"#, "buddy-tokens.json schema changed: missing 'tokens-today.date'"),
        (#"{"tokens-today": {"date": "May 28 2026", "tokens": 100}}"#, "buddy-tokens.json schema changed: invalid 'date' value"),
        (#"{"tokens-today": {"date": "2026-02-30", "tokens": 100}}"#, "buddy-tokens.json schema changed: invalid 'date' value"),
    ])
    func `schema changes are parse failures with a structural reason`(body: String, reason: String) async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        await #expect(throws: UsageError.parseFailed(reason)) {
            try await readBody(harness, body)
        }
    }

    @Test(arguments: ["-5", "74422.5"])
    func `a negative or fractional token count is a parse failure`(value: String) async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        // A token count is a whole number of tokens; a fraction is a schema
        // change, exactly like a negative count or a missing field.
        await #expect(throws: UsageError.parseFailed("buddy-tokens.json schema changed: invalid 'tokens' value")) {
            try await readBody(harness, #"{"tokens-today": {"date": "\#(Self.day(Self.now))", "tokens": \#(value)}}"#)
        }
    }

    // MARK: - Date validation against the user's local day

    @Test
    func `a stale counter is no data`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        // The file still holds an old day's total; it must never render as today's usage.
        await #expect(throws: UsageError.noData) {
            try await readBody(harness, buddyTokens("2020-01-01", 74_422))
        }
    }

    @Test
    func `a future date is no data`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        await #expect(throws: UsageError.noData) {
            try await readBody(harness, buddyTokens("2099-12-31", 100))
        }
    }

    // MARK: - The provider runs the saved choice

    @Test
    func `a provider saved to localFile mode refreshes from the file`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        try writeBuddyTokens(harness, contents: buddyTokens(Self.day(Self.now), 74_422))
        answerCLI(harness)
        let account = try localFileAccount(harness)

        let usage = try await account.provider.refresh(account)
        #expect(usage.quotas.isEmpty)
        #expect(usage.extensionMetrics?.first?.label == "Tokens Today")
        #expect(usage.extensionMetrics?.first?.value == "74,422")
        #expect(account.snapshot?.extensionMetrics?.first?.value == "74,422")
    }

    @Test
    func `a failing file surfaces its error instead of CLI data`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        // The counter is stale and the CLI is ready and willing; the daily
        // total and a five-hour window are different things, so the provider
        // must report the file's failure rather than swap data sources.
        try writeBuddyTokens(harness, contents: buddyTokens("2020-01-01", 74_422))
        answerCLI(harness)
        let account = try localFileAccount(harness)

        await #expect(throws: UsageError.noData) {
            try await account.provider.refresh(account)
        }
        #expect(account.snapshot == nil)
    }

    @Test
    func `availability in localFile mode answers for the file alone`() async throws {
        var harness = try ClaudeHarness()
        harness.now = Self.now
        defer { harness.cleanUp() }

        // The CLI would answer, but the user chose file mode because CLI/API
        // data does not apply to their setup — a missing file is unavailable.
        answerCLI(harness)
        let account = try localFileAccount(harness)
        #expect(await account.provider.isAvailable(account) == false)

        try writeBuddyTokens(harness, contents: buddyTokens(Self.day(Self.now), 100))
        #expect(await account.provider.isAvailable(account) == true)
    }

    @Test
    func `background refresh has no floor in localFile mode`() throws {
        // Reading a small local file is cheap; the user's interval stands.
        var harness = try ClaudeHarness()
        defer { harness.cleanUp() }
        let account = try localFileAccount(harness)
        #expect(account.provider.backgroundRefreshFloor == nil)
    }
}
