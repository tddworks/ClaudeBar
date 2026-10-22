import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The page asks each login for its days in a week and the week before, and
/// hands them to `Recap` by provider — two logins of one provider as one
/// (CANONICAL §5, `Recap`).
@MainActor
@Suite
struct RecapBuilderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    /// A login whose log holds `stats`, answering each range with the days
    /// that fall in it — as `UsageHistory.days(in:)` does.
    private func login(_ provider: String, _ stats: [DailyUsageStat], knowsCost: Bool = true) -> RecapLogin {
        RecapLogin(providerId: provider) { range in
            Days(stats.filter { range.contains($0.date, calendar: self.calendar) }, knowsCost: knowsCost)
        }
    }

    private func day(_ day: Int, cost: Decimal) -> DailyUsageStat {
        DailyUsageStat(date: date(day), totalCost: cost, totalTokens: 10, workingTime: 0, sessionCount: 1)
    }

    @Test func `should add two logins of one provider into that provider's one part`() async {
        let recaps = await RecapBuilder.recaps(of: [login("a", [day(20, cost: 4)]), login("a", [day(21, cost: 6)])],
                                               at: date(22), calendar: calendar)

        #expect(recaps[.thisWeek]?.providers == [Recap.Part(provider: "a", value: 10, share: 1)])
    }

    /// This week is compared with last week, and last week with the week before.
    @Test func `should compare each week with the week before it`() async {
        let recaps = await RecapBuilder.recaps(of: [login("a", [day(21, cost: 12), day(14, cost: 10), day(7, cost: 5)])],
                                               at: date(22), calendar: calendar)

        #expect(recaps[.thisWeek]?.total == 12)
        #expect(recaps[.thisWeek]?.change == 0.2)
        #expect(recaps[.lastWeek]?.total == 10)
        #expect(recaps[.lastWeek]?.change == 1)
    }

    /// A quiet week is still a recap, so the page can say it held nothing.
    @Test func `should read an empty week as an empty recap`() async {
        let recaps = await RecapBuilder.recaps(of: [login("a", [day(14, cost: 10)])], at: date(22), calendar: calendar)

        #expect(recaps[.thisWeek]?.isEmpty == true)
        #expect(recaps[.lastWeek]?.isEmpty == false)
    }
}
