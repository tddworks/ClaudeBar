import Testing
import Foundation
@testable import Domain

/// *WEEKLY RECAP*: both weeks across the lineup, each against the week before
/// it, two logins of one provider as one — read again only when the week
/// turned or a login's days were read again (CANONICAL §5, `WeeklyRecaps`).
@MainActor
@Suite
struct WeeklyRecapsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func day(_ day: Int, cost: Decimal) -> DailyUsageStat {
        DailyUsageStat(date: date(day), totalCost: cost, totalTokens: 10, workingTime: 0, sessionCount: 1)
    }

    /// A login's log, kept in memory: what it last read, and how many times
    /// the recap asked it for days.
    private final class Log {
        var stats: [DailyUsageStat]
        var lastRead: Days?
        var asked = 0
        init(_ stats: [DailyUsageStat]) {
            self.stats = stats
            lastRead = Days(stats, knowsCost: true)
        }
    }

    /// A login whose log answers each range with the days that fall in it —
    /// as `UsageHistory.days(in:)` does.
    private func login(_ provider: String, _ log: Log) -> RecapLogin {
        RecapLogin(providerId: provider, lastRead: { log.lastRead }) { range in
            log.asked += 1
            return Days(log.stats.filter { range.contains($0.date, calendar: self.calendar) }, knowsCost: true)
        }
    }

    private func recaps(_ logins: [RecapLogin], now: @escaping () -> Date) -> WeeklyRecaps {
        WeeklyRecaps(logins: { logins }, now: now, calendar: calendar)
    }

    @Test func `should read this week against last week and last week against the week before`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(14, cost: 10), day(7, cost: 5)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .thisWeek)?.total == 12)
        #expect(recaps.recap(for: .thisWeek)?.change == 0.2)
        #expect(recaps.recap(for: .lastWeek)?.total == 10)
        #expect(recaps.recap(for: .lastWeek)?.change == 1)
    }

    @Test func `should add two logins of one provider into that provider's one part`() async {
        let recaps = recaps([login("a", Log([day(20, cost: 4)])), login("a", Log([day(21, cost: 6)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .thisWeek)?.providers == [Recap.Part(provider: "a", value: 10, share: 1)])
    }

    /// A quiet week is still a recap, so the card can say it held nothing.
    @Test func `should read an empty week as an empty recap`() async {
        let recaps = recaps([login("a", Log([day(14, cost: 10)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .thisWeek)?.isEmpty == true)
        #expect(recaps.recap(for: .lastWeek)?.isEmpty == false)
    }

    @Test func `should read again when the week turns`() async {
        var today = date(22)
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(27, cost: 3)]))]) { today }
        await recaps.readIfStale()

        today = date(27)
        await recaps.readIfStale()

        #expect(recaps.recap(for: .thisWeek)?.total == 3)
        #expect(recaps.recap(for: .lastWeek)?.total == 12)
    }

    @Test func `should read again when a login's usage was read again`() async {
        let log = Log([day(21, cost: 12)])
        let recaps = recaps([login("a", log)]) { self.date(22) }
        await recaps.readIfStale()

        log.stats.append(day(22, cost: 8))
        log.lastRead = Days(log.stats, knowsCost: true)
        await recaps.readIfStale()

        #expect(recaps.recap(for: .thisWeek)?.total == 20)
    }

    @Test func `should not read again when nothing changed`() async {
        let log = Log([day(21, cost: 12)])
        let recaps = recaps([login("a", log)]) { self.date(22) }
        await recaps.readIfStale()
        let asked = log.asked

        await recaps.readIfStale()

        #expect(log.asked == asked)
        #expect(recaps.recap(for: .thisWeek)?.total == 12)
    }

    @Test func `should hold no recap before it is read`() {
        let recaps = recaps([login("a", Log([day(21, cost: 12)]))]) { self.date(22) }

        #expect(recaps.recap(for: .thisWeek) == nil)
    }
}
