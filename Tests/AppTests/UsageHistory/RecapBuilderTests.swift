import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap is the one read that spans logins: it adds every login's days
/// up for the person's total, and names the providers it spans (CANONICAL §5,
/// `Recap`).
@Suite
struct RecapBuilderTests {

    private func login(_ provider: String, _ days: [DailyUsageStat]) -> RecapLogin {
        RecapLogin(providerId: provider, days: Days(days, knowsCost: true))
    }

    private func day(_ cost: Decimal, tokens: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: Date(timeIntervalSince1970: 1_760_000_000), totalCost: cost,
                       totalTokens: tokens, workingTime: 0, sessionCount: 1)
    }

    @Test func `should add two logins of one provider into that provider's one share`() {
        let recap = RecapBuilder.build([login("claude", [day(4)]), login("claude", [day(6)])],
                                       previous: [], knowsCost: true)

        #expect(recap.providers.count == 1)
        #expect(recap.providers[0].cost == 10)
        #expect(recap.totals.cost == 10)
    }

    @Test func `should name every provider the recap spans, largest first`() {
        let recap = RecapBuilder.build([login("claude", [day(4)]), login("codex", [day(6)])],
                                       previous: [], knowsCost: true)

        #expect(recap.providers.map(\.provider) == ["codex", "claude"])
    }

    @Test func `should compare the range with the one before it`() {
        let recap = RecapBuilder.build([login("claude", [day(12)])],
                                       previous: [login("claude", [day(10)])], knowsCost: true)

        #expect(recap.previous?.cost == 10)
        #expect(recap.changePercent == 20)
    }
}