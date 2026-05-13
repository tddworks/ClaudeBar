import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct OpenCodeUsageProbeTests {

    // MARK: - isAvailable

    @Test
    func `isAvailable returns true when opencode binary is found`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("opencode")).willReturn("/usr/local/bin/opencode")

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when opencode not found`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("opencode")).willReturn(nil)

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        #expect(await probe.isAvailable() == false)
    }

    // MARK: - probe (happy path)

    @Test
    func `probe returns three quotas with correct percentages when user has usage`() async throws {
        let mockExecutor = MockCLIExecutor()
        let captured = CapturedSQL()
        given(mockExecutor).locate(.value("opencode")).willReturn("/usr/local/bin/opencode")
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, args, _, _, _, _ in
                let sql = args.dropFirst().first ?? ""
                let idx = captured.append(sql)
                // First call: primary window (5h + weekly + anchor). Second: monthly cost.
                let output: String
                if idx == 0 {
                    output = """
                    [{"five_hour_cost":2.5,"weekly_cost":7.5,"five_hour_oldest_ms":1710000000000,"anchor_ms":1700000000000}]
                    """
                } else {
                    output = """
                    [{"monthly_cost":15.0}]
                    """
                }
                return CLIResult(output: output, exitCode: 0)
            }

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "opencode-go")
        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "opencode-go" })

        // 2.5/12 used → 79.166...% remaining
        let fiveHour = snapshot.quotas.first { $0.quotaType == .session }
        #expect(fiveHour != nil)
        #expect(abs((fiveHour?.percentRemaining ?? 0) - (1 - 2.5 / 12) * 100) < 0.0001)

        // 7.5/30 used → 75% remaining
        let weekly = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weekly?.percentRemaining == 75)

        // 15/60 used → 75% remaining
        let monthly = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        #expect(monthly?.percentRemaining == 75)

        #expect(captured.count == 2)
    }

    @Test
    func `probe returns all 100 percent and skips monthly query when no usage exists`() async throws {
        let mockExecutor = MockCLIExecutor()
        let captured = CapturedSQL()
        given(mockExecutor).locate(.value("opencode")).willReturn("/usr/local/bin/opencode")
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, args, _, _, _, _ in
                _ = captured.append(args.dropFirst().first ?? "")
                // anchor_ms = null signals no opencode-go usage yet
                return CLIResult(
                    output: """
                    [{"five_hour_cost":0,"weekly_cost":0,"five_hour_oldest_ms":null,"anchor_ms":null}]
                    """,
                    exitCode: 0
                )
            }

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.allSatisfy { $0.percentRemaining == 100 })
        #expect(captured.count == 1) // monthly query was skipped
    }

    @Test
    func `probe throws cliNotFound when opencode binary missing`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("opencode")).willReturn(nil)

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        await #expect(throws: ProbeError.cliNotFound("opencode")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on non-zero exit`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("opencode")).willReturn("/usr/local/bin/opencode")
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "", exitCode: 1))

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    // MARK: - SQL shape

    @Test
    func `probe queries are filtered by providerID with JSON guards`() async throws {
        let mockExecutor = MockCLIExecutor()
        let captured = CapturedSQL()
        given(mockExecutor).locate(.value("opencode")).willReturn("/usr/local/bin/opencode")
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, args, _, _, _, _ in
                let sql = args.dropFirst().first ?? ""
                let idx = captured.append(sql)
                let output = idx == 0
                    ? """
                      [{"five_hour_cost":0,"weekly_cost":0,"five_hour_oldest_ms":null,"anchor_ms":1700000000000}]
                      """
                    : """
                      [{"monthly_cost":0}]
                      """
                return CLIResult(output: output, exitCode: 0)
            }

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        _ = try await probe.probe()

        // Both queries must filter to opencode-go assistant messages with json guards
        for sql in captured.all {
            #expect(sql.contains("json_extract(data, '$.providerID') = 'opencode-go'"))
            #expect(sql.contains("json_extract(data, '$.role') = 'assistant'"))
            #expect(sql.contains("json_valid(data)"))
            #expect(sql.contains("json_type(data, '$.cost') IN ('integer', 'real')"))
            #expect(sql.contains("COALESCE(json_extract(data, '$.time.created'), time_created)"))
        }
    }

    @Test
    func `probe passes located binary path to executor (avoids double which)`() async throws {
        let mockExecutor = MockCLIExecutor()
        let captured = CapturedSQL()
        given(mockExecutor).locate(.value("opencode")).willReturn("/opt/homebrew/bin/opencode")
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, _, _, _, _, _ in
                _ = captured.appendBinary(binary)
                return CLIResult(
                    output: """
                    [{"five_hour_cost":0,"weekly_cost":0,"five_hour_oldest_ms":null,"anchor_ms":null}]
                    """,
                    exitCode: 0
                )
            }

        let probe = OpenCodeUsageProbe(cliExecutor: mockExecutor)
        _ = try await probe.probe()

        #expect(captured.allBinaries.allSatisfy { $0 == "/opt/homebrew/bin/opencode" })
    }

    // MARK: - Parsing

    @Test
    func `parsePrimaryWindow decodes all fields including null anchor`() throws {
        let withAnchor = Data("""
        [{"five_hour_cost":1.2,"weekly_cost":3.4,"five_hour_oldest_ms":1700000000000,"anchor_ms":1690000000000}]
        """.utf8)
        let primary = try OpenCodeUsageProbe.parsePrimaryWindow(withAnchor)
        #expect(primary.fiveHourCost == 1.2)
        #expect(primary.weeklyCost == 3.4)
        #expect(primary.fiveHourOldestMs == 1_700_000_000_000)
        #expect(primary.anchorMs == 1_690_000_000_000)

        let noAnchor = Data("""
        [{"five_hour_cost":0,"weekly_cost":0,"five_hour_oldest_ms":null,"anchor_ms":null}]
        """.utf8)
        let empty = try OpenCodeUsageProbe.parsePrimaryWindow(noAnchor)
        #expect(empty.anchorMs == nil)
        #expect(empty.fiveHourOldestMs == nil)
    }

    @Test
    func `parseMonthlyCost returns sum and 0 on empty`() throws {
        let data = Data("""
        [{"monthly_cost":42.5}]
        """.utf8)
        #expect(try OpenCodeUsageProbe.parseMonthlyCost(data) == 42.5)

        let empty = Data("[]".utf8)
        #expect(try OpenCodeUsageProbe.parseMonthlyCost(empty) == 0)
    }

    @Test
    func `percentRemaining clamps to 100 and 0`() {
        #expect(OpenCodeUsageProbe.percentRemaining(used: -5, limit: 12) == 100)
        #expect(OpenCodeUsageProbe.percentRemaining(used: 20, limit: 12) == 0)
        #expect(OpenCodeUsageProbe.percentRemaining(used: 6, limit: 12) == 50)
    }

    // MARK: - Time helpers

    @Test
    func `fiveHourResetDate uses oldestMs plus five hours`() {
        let oldestMs: Int64 = 1_700_000_000_000
        let reset = OpenCodeUsageProbe.fiveHourResetDate(from: oldestMs, fallback: .distantPast)
        let expected = Date(timeIntervalSince1970: TimeInterval(oldestMs) / 1000)
            .addingTimeInterval(5 * 3600)
        #expect(reset == expected)
    }

    @Test
    func `startOfWeekUTC returns Monday 00 00 UTC for any weekday`() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        // 2024-03-13 is a Wednesday in UTC
        let wed = utc.date(from: DateComponents(year: 2024, month: 3, day: 13, hour: 18, minute: 30))!
        let weekStart = OpenCodeUsageProbe.startOfWeekUTC(from: wed)
        let comps = utc.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: weekStart)
        #expect(comps.year == 2024)
        #expect(comps.month == 3)
        #expect(comps.day == 11)        // Monday
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(comps.weekday == 2)     // Monday (Sunday=1)

        // 2024-03-17 is a Sunday in UTC — should map back to Mon Mar 11
        let sun = utc.date(from: DateComponents(year: 2024, month: 3, day: 17, hour: 23, minute: 30))!
        let sunWeekStart = OpenCodeUsageProbe.startOfWeekUTC(from: sun)
        let sunComps = utc.dateComponents([.month, .day], from: sunWeekStart)
        #expect(sunComps.month == 3)
        #expect(sunComps.day == 11)
    }

    @Test
    func `endOfWeekUTC is exactly seven days after startOfWeekUTC`() {
        let now = Date()
        let start = OpenCodeUsageProbe.startOfWeekUTC(from: now)
        let end = OpenCodeUsageProbe.endOfWeekUTC(from: now)
        #expect(end.timeIntervalSince(start) == 7 * 24 * 3600)
    }

    @Test
    func `anchoredMonthBounds preserves anchor day-of-month`() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        // Anchor: 2024-03-14 14:30 UTC ; Now: 2024-04-02 10:00 UTC
        // Expected current window: [Mar 14 14:30, Apr 14 14:30)
        let anchor = utc.date(from: DateComponents(year: 2024, month: 3, day: 14, hour: 14, minute: 30))!
        let now = utc.date(from: DateComponents(year: 2024, month: 4, day: 2, hour: 10, minute: 0))!
        let bounds = OpenCodeUsageProbe.anchoredMonthBounds(now: now, anchor: anchor)

        let startComps = utc.dateComponents([.year, .month, .day, .hour, .minute], from: bounds.start)
        #expect(startComps.year == 2024)
        #expect(startComps.month == 3)
        #expect(startComps.day == 14)
        #expect(startComps.hour == 14)
        #expect(startComps.minute == 30)

        let endComps = utc.dateComponents([.year, .month, .day, .hour, .minute], from: bounds.end)
        #expect(endComps.month == 4)
        #expect(endComps.day == 14)
        #expect(endComps.hour == 14)
        #expect(endComps.minute == 30)
    }

    @Test
    func `anchoredMonthBounds rolls back when candidate is in the future`() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        // Anchor day 20; now = April 5 (before April 20) → window starts Mar 20.
        let anchor = utc.date(from: DateComponents(year: 2024, month: 1, day: 20, hour: 9))!
        let now = utc.date(from: DateComponents(year: 2024, month: 4, day: 5, hour: 12))!
        let bounds = OpenCodeUsageProbe.anchoredMonthBounds(now: now, anchor: anchor)

        let startComps = utc.dateComponents([.month, .day, .hour], from: bounds.start)
        #expect(startComps.month == 3)
        #expect(startComps.day == 20)
        #expect(startComps.hour == 9)
    }
}

// MARK: - Test helpers

/// Thread-safe collector for SQL/binary captures from the mock executor's `willProduce` closure.
private final class CapturedSQL: @unchecked Sendable {
    private let lock = NSLock()
    private var sqls: [String] = []
    private var binaries: [String] = []

    @discardableResult
    func append(_ sql: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        sqls.append(sql)
        return sqls.count - 1
    }

    @discardableResult
    func appendBinary(_ binary: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        binaries.append(binary)
        return binaries.count - 1
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return sqls.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return sqls }
    var allBinaries: [String] { lock.lock(); defer { lock.unlock() }; return binaries }
}
