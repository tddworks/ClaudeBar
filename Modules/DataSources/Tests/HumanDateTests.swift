import Foundation
import Testing
@testable import DataSources

/// `humanDate(text)` — reset times as CLIs print them, turned into the next
/// instant they name. Ported from `ClaudeUsageProbeTests`' `parseResetDate`
/// tests, on a fixed clock so every expectation is exact.
@Suite
struct HumanDateTests {
    /// 2026-06-15 12:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_781_524_800)

    private func parse(_ text: String, now: Date = now) -> Date? {
        HumanDate.parse(text, now: now)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in zone: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// A wall-clock time in the zone the app runs in, for texts without a zone.
    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Relative durations

    @Test
    func `parses reset date with days hours and minutes`() {
        #expect(parse("resets in 2d") == Self.now.addingTimeInterval(2 * 86400))
        #expect(parse("resets in 2h 15m") == Self.now.addingTimeInterval(2 * 3600 + 15 * 60))
        #expect(parse("30m") == Self.now.addingTimeInterval(30 * 60))
        #expect(parse("in 2h") == Self.now.addingTimeInterval(7200))
    }

    @Test
    func `parses spelled out units`() {
        #expect(parse("Resets in 2 hours 5 min") == Self.now.addingTimeInterval(2 * 3600 + 5 * 60))
        #expect(parse("1 day") == Self.now.addingTimeInterval(86400))
        #expect(parse("10 minutes") == Self.now.addingTimeInterval(600))
    }

    @Test
    func `returns nil for invalid input`() {
        #expect(parse("") == nil)
        #expect(parse("no time here") == nil)
    }

    // MARK: - Absolute times

    @Test
    func `parses reset date with time only and timezone`() {
        // 8am in New York: 4:59pm is still ahead today.
        #expect(parse("Resets 4:59pm (America/New_York)") == date(2026, 6, 15, 16, 59, in: "America/New_York"))
    }

    @Test
    func `a time already past today resolves to tomorrow`() {
        // 6pm in New York: 4:59pm has gone, so tomorrow's.
        let evening = date(2026, 6, 15, 18, 0, in: "America/New_York")

        #expect(parse("Resets 4:59pm (America/New_York)", now: evening) == date(2026, 6, 16, 16, 59, in: "America/New_York"))
    }

    @Test
    func `parses reset date with short time and timezone`() {
        // 8pm in Shanghai: 3pm has gone, so tomorrow's.
        #expect(parse("Resets 3pm (Asia/Shanghai)") == date(2026, 6, 16, 15, 0, in: "Asia/Shanghai"))
    }

    @Test
    func `parses reset date with month day and time with timezone`() {
        #expect(parse("Resets Dec 25 at 4:59am (Asia/Shanghai)") == date(2026, 12, 25, 4, 59, in: "Asia/Shanghai"))
    }

    @Test
    func `parses reset date with month day comma time and timezone`() {
        // January 15 has passed this year, so next year's.
        #expect(parse("Resets Jan 15, 3:30pm (America/Los_Angeles)") == date(2027, 1, 15, 15, 30, in: "America/Los_Angeles"))
    }

    @Test
    func `parses reset date with month day comma short time`() {
        #expect(parse("Resets Feb 12 at 4pm (Asia/Shanghai)") == date(2027, 2, 12, 16, 0, in: "Asia/Shanghai"))
        #expect(parse("Resets Jul 2 at 4:59am (America/Chicago)") == date(2026, 7, 2, 4, 59, in: "America/Chicago"))
    }

    @Test
    func `parses reset date with month day comma time without timezone`() {
        #expect(parse("Resets Jan 15, 3:30pm") == local(2027, 1, 15, 15, 30))
    }

    @Test
    func `parses reset date with month day year and timezone`() {
        #expect(parse("Resets Jan 1, 2027 (America/New_York)") == date(2027, 1, 1, 0, 0, in: "America/New_York"))
    }

    @Test
    func `a date with a year is kept even when it has passed`() {
        #expect(parse("Resets Jan 1, 2026 (America/New_York)") == date(2026, 1, 1, 0, 0, in: "America/New_York"))
    }

    @Test
    func `parses reset date with month day only`() {
        // Start of that day.
        #expect(parse("Resets Dec 28") == local(2026, 12, 28))
    }

    @Test
    func `parsed absolute date has correct timezone`() {
        // The same wall-clock time in different zones is a different instant.
        let eastern = parse("Resets 4:59pm (America/New_York)")
        let shanghai = parse("Resets 4:59pm (Asia/Shanghai)")

        #expect(eastern == date(2026, 6, 15, 20, 59))
        #expect(shanghai == date(2026, 6, 16, 8, 59))
        #expect(eastern != shanghai, "Same wall-clock time in different timezones should produce different Dates")
    }

    // MARK: - Text around the time

    @Test
    func `ignores a percentage sharing the line`() {
        #expect(parse("Resets 3pm (Europe/Amsterdam)                      27% used") == date(2026, 6, 15, 15, 0, in: "Europe/Amsterdam"))
    }

    @Test
    func `reads the time after the last Resets on the line`() {
        #expect(parse("$5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)") == date(2026, 1, 1, 0, 0, in: "America/New_York"))
        #expect(parse("Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)") == date(2026, 6, 15, 16, 59, in: "America/New_York"))
    }
}
