import Testing
import Domain
@testable import ClaudeBar

/// The words on a quota card. An outlined theme (Pop) prints them the
/// design's way: a short "left"/"used" beside the number, and the reset
/// line's time picked out in bold.
@Suite
struct QuotaCardTextTests {
    // MARK: - Caption

    @Test func `a glass theme keeps the full caption`() {
        #expect(QuotaCardText.caption(mode: .remaining, isOutlined: false) == "Remaining")
        #expect(QuotaCardText.caption(mode: .used, isOutlined: false) == "Used")
        #expect(QuotaCardText.caption(mode: .pace, isOutlined: false) == "Remaining")
    }

    @Test func `an outlined theme says left or used, beside the number`() {
        #expect(QuotaCardText.caption(mode: .remaining, isOutlined: true) == "left")
        #expect(QuotaCardText.caption(mode: .used, isOutlined: true) == "used")
        #expect(QuotaCardText.caption(mode: .pace, isOutlined: true) == "left")
    }

    // MARK: - Reset line

    @Test func `a countdown splits into its lead and the time`() {
        let line = QuotaCardText.ResetLine("Resets in 2h 4m")
        #expect(line.lead == "Resets in")
        #expect(line.time == "2h 4m")
    }

    @Test func `a reset day splits after Resets`() {
        let line = QuotaCardText.ResetLine("Resets Tue 9:00")
        #expect(line.lead == "Resets")
        #expect(line.time == "Tue 9:00")
    }

    @Test func `resetting soon picks out soon`() {
        let line = QuotaCardText.ResetLine("Resets soon")
        #expect(line.lead == "Resets")
        #expect(line.time == "soon")
    }

    @Test func `a narrow card keeps only the time`() {
        let line = QuotaCardText.ResetLine(time: "3d 10h 59m")
        #expect(line.lead.isEmpty)
        #expect(line.time == "3d 10h 59m")
    }

    @Test func `any other text is all lead, nothing in bold`() {
        let line = QuotaCardText.ResetLine("Renews monthly")
        #expect(line.lead == "Renews monthly")
        #expect(line.time == nil)
    }
}

/// The words on a budget card as an outlined theme (Pop) prints them.
@Suite
struct BudgetCardTextTests {
    @Test func `extra usage is a month's spend, API cost just a spend`() {
        #expect(QuotaCardText.spentLabel(for: .extraUsage) == "SPENT THIS MONTH")
        #expect(QuotaCardText.spentLabel(for: .apiCost) == "SPENT")
    }

    @Test func `the budget's status reads as a phrase, not a badge`() {
        #expect(QuotaCardText.budgetPhrase(.withinBudget) == "On track")
        #expect(QuotaCardText.budgetPhrase(.approachingLimit) == "Near limit")
        #expect(QuotaCardText.budgetPhrase(.overBudget) == "Over budget")
    }
}
