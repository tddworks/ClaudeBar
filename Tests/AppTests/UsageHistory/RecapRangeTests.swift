import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap's range choice is the page's own: *This week* is the week that
/// holds today, *Last week* the one before it — each a week of the person's
/// calendar, and each compared with the week before it.
@Suite
struct RecapRangeTests {
    private let calendar = DataSources.calendar()
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func `should name the week that holds today`() {
        let week = RecapRange.thisWeek.range(containing: now, calendar: calendar)

        #expect(week.contains(now, calendar: calendar))
        #expect(week.days(in: calendar).count == 7)
    }

    @Test func `should name the week before when last week is chosen`() {
        let thisWeek = RecapRange.thisWeek.range(containing: now, calendar: calendar)
        let lastWeek = RecapRange.lastWeek.range(containing: now, calendar: calendar)

        #expect(lastWeek == thisWeek.before(calendar: calendar))
        #expect(!lastWeek.contains(now, calendar: calendar))
    }

    @Test func `should name the week each range is compared with`() {
        #expect(RecapRange.thisWeek.comparedWith == "vs last week")
        #expect(RecapRange.lastWeek.comparedWith == "vs the week before")
    }
}