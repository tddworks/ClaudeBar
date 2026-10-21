import Foundation
import Testing
@testable import Quotas

/// A recap is a read of a range, told as a few highlights — the total, the
/// split by provider, the top model, the biggest day, the savings, and the
/// range before it. The one read that may sum across logins (CANONICAL §5,
/// `Recap`).
@Suite
struct RecapTests {
    private let day0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let day1 = Date(timeIntervalSince1970: 1_760_086_400)
    private let day2 = Date(timeIntervalSince1970: 1_760_172_800)

    /// A day with only the fields a test names set.
    private func day(_ date: Date, cost: Decimal = 0, tokens: Int = 0, cacheWrite: Int = 0,
                     cacheRead: Int = 0, workingTime: TimeInterval = 0, sessions: Int = 1,
                     savings: Decimal = 0, lines: [ModelUsageLine] = []) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: workingTime,
                       sessionCount: sessions, cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead,
                       cachedSavings: savings, lines: lines)
    }

    /// A provider's days as one span.
    private func span(_ provider: String, _ days: [DailyUsageStat]) -> Recap.Span {
        Recap.Span(provider: provider, days: days)
    }

    private let opus = ModelUsageLine(model: "claude-opus-4-6", totalTokens: 100, cost: 12)
    private let sonnet = ModelUsageLine(model: "claude-sonnet-5", totalTokens: 400, cost: 2)

    /// Every login's days land in one total.
    @Test func `should add the week up across every login's days`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 10, tokens: 1_000, workingTime: 3_600, sessions: 2)]),
            span("codex", [day(day0, cost: 5, tokens: 2_000, workingTime: 1_800, sessions: 1),
                           day(day1, cost: 2, tokens: 500, workingTime: 600, sessions: 1)]),
        ], knowsCost: true)

        #expect(recap.totals.cost == 17)
        #expect(recap.totals.tokens == 3_500)
        #expect(recap.totals.workingTime == 6_000)
        #expect(recap.totals.sessions == 4)
    }

    /// The split names each provider and orders it by its part.
    @Test func `should name the providers it spans, largest first`() {
        let recap = Recap(spans: [
            span("codex", [day(day0, cost: 5, tokens: 2_000)]),
            span("claude", [day(day0, cost: 15, tokens: 1_000)]),
        ], knowsCost: true)

        #expect(recap.providers.map(\.provider) == ["claude", "codex"])
        #expect(recap.formattedShare(of: recap.providers[0]) == "75%")
    }

    /// One provider, however many logins, is one share.
    @Test func `should add two logins of one provider into one share`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 4, tokens: 100)]),
            span("claude", [day(day0, cost: 6, tokens: 200)]),
        ], knowsCost: true)

        #expect(recap.providers.count == 1)
        #expect(recap.providers[0].cost == 10)
        #expect(recap.providers[0].tokens == 300)
    }

    /// The top model is the one whose lines spent the most.
    @Test func `should find the model that spent the most`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, lines: [opus, sonnet]), day(day1, lines: [sonnet])]),
        ], knowsCost: true)

        #expect(recap.topModel?.model == "claude-opus-4-6")
        #expect(recap.topModel?.displayName == "opus-4-6")
    }

    /// The biggest day is the one day every provider adds up to most.
    @Test func `should find the day that added up to the most, across providers`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 3), day(day1, cost: 4)]),
            span("codex", [day(day1, cost: 5)]),
        ], knowsCost: true)

        #expect(recap.biggestDay?.date == day1)
        #expect(recap.biggestDay?.cost == 9)
    }

    /// The savings are the range's own, summed over its days.
    @Test func `should sum what caching saved across the range`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 1, savings: Decimal(string: "2.50")!),
                            day(day1, cost: 1, savings: Decimal(string: "1.25")!)]),
        ], knowsCost: true)

        #expect(recap.cacheSavings == Decimal(string: "3.75")!)
        #expect(recap.formattedSavings == "$3.75")
    }

    /// The change is the range against the one before it.
    @Test func `should compare the range with the one before it`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 12)]),
        ], previous: [
            span("claude", [day(day0, cost: 10)]),
        ], knowsCost: true)

        #expect(recap.previous?.cost == 10)
        #expect(recap.changePercent == 20)
        #expect(recap.formattedChange == "+20%")
    }

    /// Nothing before means no change to show, never a minus hundred percent.
    @Test func `should offer no comparison when the range before held nothing`() {
        let recap = Recap(spans: [span("claude", [day(day0, cost: 12)])],
                          previous: [span("claude", [day(day0)])], knowsCost: true)

        #expect(recap.previous == nil)
        #expect(recap.changePercent == nil)
        #expect(recap.formattedChange == nil)
    }

    /// An empty range is empty, so the card can stay away.
    @Test func `should show nothing rather than zeros when the range holds nothing`() {
        let empty = Recap(spans: [span("claude", [day(day0), day(day1)])], knowsCost: true)
        #expect(empty.isEmpty)

        let some = Recap(spans: [span("claude", [day(day0, tokens: 1)])], knowsCost: true)
        #expect(!some.isEmpty)
    }

    /// When nothing is priced, tokens are the unit.
    @Test func `should lead with tokens when no login is priced`() {
        let recap = Recap(spans: [
            span("codex", [day(day0, cost: 0, tokens: 1_000)]),
            span("claude", [day(day0, cost: 0, tokens: 500)]),
        ], knowsCost: false)

        #expect(recap.value == 1_500)
        #expect(recap.providers.map(\.provider) == ["codex", "claude"])
        #expect(recap.formattedShare(of: recap.providers[0]) == "67%")
    }

    /// The token total counts cache writes and reads too.
    @Test func `should count every token, cache included`() {
        let recap = Recap(spans: [
            span("claude", [day(day0, cost: 1, tokens: 1_000, cacheWrite: 200, cacheRead: 800)]),
        ], knowsCost: true)

        #expect(recap.totals.tokens == 2_000)
        #expect(recap.formattedTokens == "2.0K")
    }
}