import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap's range choice in words: each range named for what it is
/// compared with, and an empty range said, never shown as zeros.
@Suite
struct RecapRangeWordsTests {
    @Test func `should say which week each range is compared with`() {
        #expect(RecapRange.thisWeek.comparedWith == "vs last week")
        #expect(RecapRange.lastWeek.comparedWith == "vs the week before")
    }

    @Test func `should say which month each range is compared with`() {
        #expect(RecapRange.thisMonth.comparedWith == "vs last month")
        #expect(RecapRange.lastMonth.comparedWith == "vs the month before")
    }

    @Test func `should say the chosen week held nothing`() {
        #expect(RecapRange.thisWeek.emptyNote == "Nothing this week.")
        #expect(RecapRange.lastWeek.emptyNote == "Nothing last week.")
    }

    @Test func `should say the chosen month held nothing`() {
        #expect(RecapRange.thisMonth.emptyNote == "Nothing this month.")
        #expect(RecapRange.lastMonth.emptyNote == "Nothing last month.")
    }

    @Test func `should name all four ranges for the chips`() {
        #expect(RecapRange.thisWeek.title == "This week")
        #expect(RecapRange.lastWeek.title == "Last week")
        #expect(RecapRange.thisMonth.title == "This month")
        #expect(RecapRange.lastMonth.title == "Last month")
    }
}
