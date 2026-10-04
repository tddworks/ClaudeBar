import DataSources
import Quotas
import Foundation
import Testing

/// Claude Code's `/cost` screen read by `claude.json`'s `cliCost` data source:
/// drawn by the terminal emulator, then `claude-cost-screen.js`.
///
/// Ported from the `/cost` part of `ClaudeUsageProbeParsingTests`; the
/// fixtures are its own, verbatim.
@Suite
struct ClaudeCostScreenTests {

    static let costCommandOutput = """
    Total cost:            $0.55
    Total duration (API):  6m 19.7s
    Total duration (wall): 6h 33m 10.2s
    Total code changes:    0 lines added, 0 lines removed
    """

    static let costCommandOutputLargeCost = """
    Total cost:            $1,234.56
    Total duration (API):  2h 30m 45.5s
    Total duration (wall): 48h 15m 30.2s
    Total code changes:    1500 lines added, 200 lines removed
    """

    // MARK: - /cost Command Parsing

    @Test
    func `parses cost command output total cost`() throws {
        let snapshot = try read(Self.costCommandOutput)

        #expect(snapshot.accountTier == .claudeApi)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "0.55"))
        #expect(snapshot.costUsage?.budget == nil)
        #expect(snapshot.costUsage?.kind == .apiCost)
        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `parses cost command output API duration`() throws {
        let snapshot = try read(Self.costCommandOutput)

        // 6m 19.7s = 6*60 + 19.7 = 379.7 seconds
        #expect(snapshot.costUsage?.apiDuration ?? 0 > 379)
        #expect(snapshot.costUsage?.apiDuration ?? 0 < 380)
    }

    @Test
    func `parses cost command with large cost and commas`() throws {
        let snapshot = try read(Self.costCommandOutputLargeCost)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1234.56"))
    }

    static let costLines: [(String, String)] = [
        ("Total cost:            $0.55", "0.55"),
        ("Total cost: $1,234.56", "1234.56"),
        ("Total cost:   0.00", "0.00"),
    ]

    @Test(arguments: costLines)
    func `extracts cost value from total cost line`(line: String, cost: String) throws {
        #expect(try read(line).costUsage?.totalCost == Decimal(string: cost))
    }

    @Test
    func `extracts API duration from duration line`() throws {
        let snapshot = try read("Total cost: $0.55\nTotal duration (API):  6m 19.7s")

        // 6*60 + 19.7 = 379.7
        #expect(snapshot.costUsage?.apiDuration ?? 0 > 379)
        #expect(snapshot.costUsage?.apiDuration ?? 0 < 380)
    }

    @Test
    func `a screen without an API duration has none`() throws {
        #expect(try read("Total cost: $0.55").costUsage?.apiDuration == 0)
    }

    static let durations: [(String, Double)] = [
        ("2h 30m", 9000),
        ("1h", 3600),
        ("45s", 45),
        ("2h 30m 45.5s", 9045.5),
        ("6m 19.7s", 379.7),
    ]

    @Test(arguments: durations)
    func `parses duration string with hours minutes seconds`(duration: String, seconds: Double) throws {
        let snapshot = try read("Total cost: $0.55\nTotal duration (API):  \(duration)")

        #expect(abs((snapshot.costUsage?.apiDuration ?? -1) - seconds) < 0.001)
    }

    // MARK: - /cost Screens That Are Not Cost Readings (issue #317)

    /// A `/cost` screen that reports a failure is not a cost of zero. The rate
    /// limit case is the one that matters: a throttled CLI still paints the
    /// panel, `$0.0000` reads off it, and the data source *succeeds* with a cost
    /// of nothing — which is both wrong and final (#317).
    @Test
    func `a rate-limited cost screen is an error rather than a cost of zero`() {
        let rateLimited = Self.costCommandOutput + "\nError: Usage endpoint is rate limited. Please try again in a moment."

        #expect(throws: UsageError.executionFailed("Rate limited - too many requests")) {
            try read(rateLimited)
        }
    }

    @Test
    func `a logged-out cost screen is an error rather than a cost of zero`() {
        let loggedOut = Self.costCommandOutput + "\nInvalid API key · Please log in with /login"

        #expect(throws: UsageError.authenticationRequired) {
            try read(loggedOut)
        }
    }

    /// A capture that ended before the cost panel was painted at all has no
    /// `Total cost` row, and says so instead of answering `$0.00`.
    @Test
    func `a capture with no cost panel is a parse failure rather than a cost of zero`() {
        let beforeThePanel = """
        Claude Code v2.1.274
        Opus 5 (1M context) with high effort · API Usage Billing
        ~/Library/Application Support/ClaudeBar/Probe
         Esc to cancel
        """

        #expect(throws: UsageError.parseFailed("Could not find total cost")) {
            try read(beforeThePanel)
        }
    }

    /// The panel is painted in full during boot, so `$0.0000` off it is the
    /// probe session's own spend, not a misread; the fix is upstream — a
    /// subscription must not be routed here at all.
    @Test
    func `a fully painted cost panel of an empty session reads as zero`() throws {
        let panelOnly = """
        Claude Code v2.1.274
        Opus 5 (1M context) with high effort · API Usage Billing
          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Total duration (wall): 1s
            Total code changes:  0 lines added, 0 lines removed
            Usage: 0 input, 0 output, 0 cache read, 0 cache write
          Esc to cancel
        """

        let snapshot = try read(panelOnly)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "0.0000"))
        #expect(snapshot.accountTier == .claudeApi)
    }

    // MARK: - Helper

    /// The screen as the `cliCost` data source reads it: rendered, then scripted.
    private func read(_ screen: String) throws -> UsageSnapshot {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        return try claude.readCostScreen(TerminalRenderer(cols: 160, rows: 50).render(screen))
    }
}
