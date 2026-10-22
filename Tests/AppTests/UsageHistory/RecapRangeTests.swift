import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap's range choice: *This week* is the calendar's week that holds
/// today, *Last week* the one before it — each compared with the week before
/// it, and each named for what it is compared with.
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

    @Test func `should say which week each range is compared with`() {
        #expect(RecapRange.thisWeek.comparedWith == "vs last week")
        #expect(RecapRange.lastWeek.comparedWith == "vs the week before")
    }

    @Test func `should say the chosen week held nothing`() {
        #expect(RecapRange.thisWeek.emptyNote == "Nothing this week.")
        #expect(RecapRange.lastWeek.emptyNote == "Nothing last week.")
    }
}
