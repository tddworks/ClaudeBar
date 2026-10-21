import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap is the one read that spans logins: it picks each week out of
/// every login's days, adds them up for the person's total, and names the
/// providers it spans (CANONICAL §5, `Recap`).
@Suite
struct RecapBuilderTests {
    private let calendar = DataSources.calendar()

    /// A day `offset` days from a fixed base, so a range's first and last day
    /// both hold it whatever the zone.
    private func date(_ offset: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    private var thisWeek: DateRange { DateRange(first: date(0), last: date(6), calendar: calendar) }

    private func day(_ cost: Decimal, on offset: Int, tokens: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date(offset), totalCost: cost, totalTokens: tokens,
                       workingTime: 0, sessionCount: 1)
    }

    private func login(_ provider: String, _ days: [DailyUsageStat], knowsCost: Bool = true) -> RecapLogin {
        RecapLogin(providerId: provider, days: Days(days, knowsCost: knowsCost))
    }

    @Test func `should add two logins of one provider into that provider's one share`() {
        let recap = RecapBuilder.build([login("claude", [day(4, on: 1)]), login("claude", [day(6, on: 2)])],
                                       in: thisWeek, calendar: calendar)

        #expect(recap.providers.count == 1)
        #expect(recap.providers[0].cost == 10)
        #expect(recap.totals.cost == 10)
    }

    @Test func `should name every provider the recap spans, largest first`() {
        let recap = RecapBuilder.build([login("claude", [day(4, on: 1)]), login("codex", [day(6, on: 2)])],
                                       in: thisWeek, calendar: calendar)

        #expect(recap.providers.map(\.provider) == ["codex", "claude"])
    }

    @Test func `should count only the days that fall in the range`() {
        let recap = RecapBuilder.build([login("claude", [day(12, on: 1), day(10, on: -3), day(9, on: -40)])],
                                       in: thisWeek, calendar: calendar)

        #expect(recap.totals.cost == 12)
        #expect(recap.providers[0].cost == 12)
    }

    @Test func `should compare the range with the one before it`() {
        let recap = RecapBuilder.build([login("claude", [day(12, on: 1), day(10, on: -3)])],
                                       in: thisWeek, calendar: calendar)

        #expect(recap.previous?.cost == 10)
        #expect(recap.changePercent == 20)
    }

    @Test func `should lead with cost when any login is priced`() {
        let recap = RecapBuilder.build([login("claude", [day(4, on: 1)]),
                                        login("ollama", [day(0, on: 2, tokens: 500)], knowsCost: false)],
                                       in: thisWeek, calendar: calendar)

        #expect(recap.knowsCost)
        #expect(recap.totals.tokens == 500)
    }
}