import Testing
import Foundation
@testable import Domain

/// The recap's two weeks: *This week* is the calendar's week that holds
/// today, *Last week* the one before it.
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
}
