import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap's range choice in words: each week named for what it is
/// compared with, and an empty week said, never shown as zeros.
@Suite
struct RecapRangeWordsTests {
    @Test func `should say which week each range is compared with`() {
        #expect(RecapRange.thisWeek.comparedWith == "vs last week")
        #expect(RecapRange.lastWeek.comparedWith == "vs the week before")
    }

    @Test func `should say the chosen week held nothing`() {
        #expect(RecapRange.thisWeek.emptyNote == "Nothing this week.")
        #expect(RecapRange.lastWeek.emptyNote == "Nothing last week.")
    }
}
