import Testing
import Foundation
@testable import Domain

/// The recap's ranges: *This week* is the calendar's week that holds today,
/// *Last week* the one before it; *This month* the calendar's month, *Last
/// month* the one before it.
@Suite
struct RecapRangeTests {
    private let calendar = DataSources.calendar()
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func `should name the calendar week that holds today as this week`() {
        #expect(RecapRange.thisWeek.range(containing: now, calendar: calendar)
                == DateRange.week(containing: now, calendar: calendar))
    }

    @Test func `should name the week before this one as last week`() {
        let thisWeek = DateRange.week(containing: now, calendar: calendar)

        #expect(RecapRange.lastWeek.range(containing: now, calendar: calendar) == thisWeek.before(calendar: calendar))
    }

    @Test func `should name the calendar month that holds today as this month`() {
        #expect(RecapRange.thisMonth.range(containing: now, calendar: calendar)
                == DateRange.month(containing: now, calendar: calendar))
    }

    @Test func `should name the month before this one as last month`() {
        let thisMonth = DateRange.month(containing: now, calendar: calendar)

        #expect(RecapRange.lastMonth.range(containing: now, calendar: calendar) == thisMonth.previousMonth(calendar: calendar))
    }

    /// What a range is read against: the same kind, one run earlier.
    @Test func `should read each week against the week before it`() {
        let week = DateRange.week(containing: now, calendar: calendar)

        #expect(RecapRange.thisWeek.rangeBefore(containing: now, calendar: calendar) == week.before(calendar: calendar))
        #expect(RecapRange.lastWeek.rangeBefore(containing: now, calendar: calendar) == week.before(calendar: calendar).before(calendar: calendar))
    }

    /// A month is read against the month before it — a month steps a month,
    /// never a day-count back.
    @Test func `should read each month against the month before it`() {
        let month = DateRange.month(containing: now, calendar: calendar)

        #expect(RecapRange.thisMonth.rangeBefore(containing: now, calendar: calendar) == month.previousMonth(calendar: calendar))
        #expect(RecapRange.lastMonth.rangeBefore(containing: now, calendar: calendar) == month.previousMonth(calendar: calendar).previousMonth(calendar: calendar))
    }
}
