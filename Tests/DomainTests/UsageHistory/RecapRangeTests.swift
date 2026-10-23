import Testing
import Foundation
@testable import Domain

/// The recap's ranges: *This week* is the calendar's week that holds today,
/// *Last week* the one before it; *This month* the calendar's month, *Last
/// month* the one before it. Each is read against its period's one before.
@Suite
struct RecapRangeTests {
    private let calendar = DataSources.calendar()
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func period(_ period: RecapPeriod) -> DateRange { period.range(containing: now, calendar: calendar) }
    private func before(_ range: DateRange, _ period: RecapPeriod) -> DateRange { period.before(range, calendar: calendar) }

    @Test func `should offer this and last of a week, then of a month`() {
        #expect(RecapRange.allCases == [.this(.week), .last(.week), .this(.month), .last(.month)])
    }

    @Test func `should name the calendar week that holds today as this week`() {
        #expect(RecapRange.this(.week).range(containing: now, calendar: calendar) == period(.week))
    }

    @Test func `should name the week before this one as last week`() {
        #expect(RecapRange.last(.week).range(containing: now, calendar: calendar) == before(period(.week), .week))
    }

    @Test func `should name the calendar month that holds today as this month`() {
        #expect(RecapRange.this(.month).range(containing: now, calendar: calendar) == period(.month))
    }

    @Test func `should name the month before this one as last month`() {
        #expect(RecapRange.last(.month).range(containing: now, calendar: calendar) == before(period(.month), .month))
    }

    @Test func `should read each week against the week before it`() {
        let week = period(.week)

        #expect(RecapRange.this(.week).rangeBefore(containing: now, calendar: calendar) == before(week, .week))
        #expect(RecapRange.last(.week).rangeBefore(containing: now, calendar: calendar) == before(before(week, .week), .week))
    }

    @Test func `should read each month against the month before it`() {
        let month = period(.month)

        #expect(RecapRange.this(.month).rangeBefore(containing: now, calendar: calendar) == before(month, .month))
        #expect(RecapRange.last(.month).rangeBefore(containing: now, calendar: calendar) == before(before(month, .month), .month))
    }
}
