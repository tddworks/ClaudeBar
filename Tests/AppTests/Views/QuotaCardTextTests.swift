import Foundation
import Testing
import Kit
@testable import ClaudeBar

/// The words on a quota card. An outlined theme (Pop) prints them the
/// design's way: a short "left"/"used" beside the number, and the reset
/// line's time picked out in bold.
@Suite
struct QuotaCardTextTests {
    // MARK: - Caption

    @Test func `should caption a quota Remaining or Used in full on a glass theme`() {
        #expect(QuotaCardText.caption(mode: .remaining, isOutlined: false) == "Remaining")
        #expect(QuotaCardText.caption(mode: .used, isOutlined: false) == "Used")
        #expect(QuotaCardText.caption(mode: .pace, isOutlined: false) == "Remaining")
    }

    @Test func `should caption a quota left or used beside the number on an outlined theme`() {
        #expect(QuotaCardText.caption(mode: .remaining, isOutlined: true) == "left")
        #expect(QuotaCardText.caption(mode: .used, isOutlined: true) == "used")
        #expect(QuotaCardText.caption(mode: .pace, isOutlined: true) == "left")
    }

    // MARK: - Headline (#499: dollars print like percentages)

    @Test func `should headline a quota with its percentage and say left beside it`() {
        let quota = UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "claude")
        let headline = QuotaCardText.headline(for: quota, mode: .remaining)
        #expect(headline == .init(number: "62%", caption: "left"))
    }

    @Test func `should headline a credit balance with its amount and say left beside it`() {
        let quota = UsageQuota(percentRemaining: 97, quotaType: .modelSpecific("Credits"), providerId: "openrouter", dollarRemaining: Decimal(string: "24.19"))
        let headline = QuotaCardText.headline(for: quota, mode: .remaining)
        #expect(headline == .init(number: "$24.19", caption: "left"))
    }

    @Test func `should headline a capped spend with what was spent and its cap beside it`() {
        let quota = UsageQuota(percentRemaining: 75, quotaType: .modelSpecific("Spend"), providerId: "cursor", dollarUsed: 125, dollarCap: 500)
        let headline = QuotaCardText.headline(for: quota, mode: .remaining)
        #expect(headline == .init(number: "$125.00", caption: "of $500"))
    }

    // MARK: - Reset line

    @Test func `should pick out the time of a reset countdown in bold`() {
        let line = QuotaCardText.ResetLine("Resets in 2h 4m")
        #expect(line.lead == "Resets in")
        #expect(line.time == "2h 4m")
    }

    @Test func `should pick out the day and time a quota resets in bold`() {
        let line = QuotaCardText.ResetLine("Resets Tue 9:00")
        #expect(line.lead == "Resets")
        #expect(line.time == "Tue 9:00")
    }

    @Test func `should pick out soon in bold when a quota resets soon`() {
        let line = QuotaCardText.ResetLine("Resets soon")
        #expect(line.lead == "Resets")
        #expect(line.time == "soon")
    }

    @Test func `should show only the reset time on a narrow card`() {
        let line = QuotaCardText.ResetLine(time: "3d 10h 59m")
        #expect(line.lead.isEmpty)
        #expect(line.time == "3d 10h 59m")
    }

    @Test func `should show any other reset text plainly, with nothing in bold`() {
        let line = QuotaCardText.ResetLine("Renews monthly")
        #expect(line.lead == "Renews monthly")
        #expect(line.time == nil)
    }
}

/// The words on a budget card as an outlined theme (Pop) prints them.
@Suite
struct BudgetCardTextTests {
    @Test func `should label extra usage as this month's spend and API cost as a spend`() {
        #expect(QuotaCardText.spentLabel(for: .extraUsage) == "SPENT THIS MONTH")
        #expect(QuotaCardText.spentLabel(for: .apiCost) == "SPENT")
    }

    @Test func `should say how a budget is going as a phrase, not a badge`() {
        #expect(QuotaCardText.budgetPhrase(.withinBudget) == "On track")
        #expect(QuotaCardText.budgetPhrase(.approachingLimit) == "Near limit")
        #expect(QuotaCardText.budgetPhrase(.overBudget) == "Over budget")
    }
}
