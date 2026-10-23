import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap's range choice in words: each range named for what it is
/// compared with, and an empty range said, never shown as zeros.
@Suite
struct RecapRangeWordsTests {
    @Test func `should say which week each range is compared with`() {
        #expect(RecapRange.this(.week).comparedWith == "vs last week")
        #expect(RecapRange.last(.week).comparedWith == "vs the week before")
    }

    @Test func `should say which month each range is compared with`() {
        #expect(RecapRange.this(.month).comparedWith == "vs last month")
        #expect(RecapRange.last(.month).comparedWith == "vs the month before")
    }

    @Test func `should say the chosen week held nothing`() {
        #expect(RecapRange.this(.week).emptyNote == "Nothing this week.")
        #expect(RecapRange.last(.week).emptyNote == "Nothing last week.")
    }

    @Test func `should say the chosen month held nothing`() {
        #expect(RecapRange.this(.month).emptyNote == "Nothing this month.")
        #expect(RecapRange.last(.month).emptyNote == "Nothing last month.")
    }

    @Test func `should name all four ranges for the chips`() {
        #expect(RecapRange.this(.week).title == "This week")
        #expect(RecapRange.last(.week).title == "Last week")
        #expect(RecapRange.this(.month).title == "This month")
        #expect(RecapRange.last(.month).title == "Last month")
    }
}
