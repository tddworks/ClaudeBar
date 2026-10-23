import Testing
import Foundation
@testable import Domain

/// *RECAP*: both weeks and both months across the lineup, each against the
/// period before it, two logins of one provider as one — read again only when the week
/// or month turned or a login's days were read again (CANONICAL §5, `Recaps`).
@MainActor
@Suite
struct RecapsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func week(_ day: Int) -> DateRange {
        DateRange.week(containing: date(day), calendar: calendar)
    }

    /// A day in a named month, for the months the recap reads.
    private func day(_ month: Int, _ dayOfMonth: Int, cost: Decimal) -> DailyUsageStat {
        DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth))!,
                       totalCost: cost, totalTokens: 10, workingTime: 0, sessionCount: 1)
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

    private func recaps(_ logins: [RecapLogin], now: @escaping () -> Date) -> Recaps {
        Recaps(logins: { logins }, now: now, calendar: calendar)
    }

    @Test func `should read this week against last week and last week against the week before`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(14, cost: 10), day(7, cost: 5)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.total == 12)
        #expect(recaps.recap(for: .this(.week))?.change == 0.2)
        #expect(recaps.recap(for: .last(.week))?.total == 10)
        #expect(recaps.recap(for: .last(.week))?.change == 1)
    }

    @Test func `should add two logins of one provider into that provider's one part`() async {
        let recaps = recaps([login("a", Log([day(20, cost: 4)])), login("a", Log([day(21, cost: 6)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.providers == [Recap.Part(provider: "a", value: 10, share: 1)])
    }

    /// A quiet week is still a recap, so the card can say it held nothing.
    @Test func `should read an empty week as an empty recap`() async {
        let recaps = recaps([login("a", Log([day(14, cost: 10)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.isEmpty == true)
        #expect(recaps.recap(for: .last(.week))?.isEmpty == false)
    }

    @Test func `should read again when the week turns`() async {
        var today = date(22)
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(27, cost: 3)]))]) { today }
        await recaps.readIfStale()

        today = date(27)
        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.total == 3)
        #expect(recaps.recap(for: .last(.week))?.total == 12)
    }

    /// The month recap reads the calendar's month against the one before it.
    @Test func `should read this month against last month and last month against the month before`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(10, cost: 5), day(9, 20, cost: 8)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.month))?.total == 17)
        #expect(recaps.recap(for: .this(.month))?.change == 1.125)
        #expect(recaps.recap(for: .last(.month))?.total == 8)
        #expect(recaps.recap(for: .last(.month))?.change == nil)
    }

    /// October 31 and November 1, 2026 share the Monday-first week Oct 26 –
    /// Nov 1, yet the month turned: the recaps are read again.
    @Test func `should read again when the month turns inside the same week`() async {
        var today = date(31)
        let recaps = recaps([login("a", Log([day(31, cost: 12), day(5, cost: 9)]))]) { today }
        await recaps.readIfStale()

        today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.month))?.isEmpty == true)
        #expect(recaps.recap(for: .last(.month))?.total == 21)
    }

    /// Each recap says which days it sums — what a report writes in its
    /// header and a sender checks.
    @Test func `should give each recap the days it was read for`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.range == week(22))
        #expect(recaps.recap(for: .last(.week))?.range == week(14))
        #expect(recaps.recap(for: .last(.month))?.range
                == DateRange(first: date(1).addingTimeInterval(-30 * 86_400), last: date(1).addingTimeInterval(-86_400),
                             calendar: calendar))
    }

    /// Last week is this week's *before*, and last month this month's: six
    /// ranges, each asked once.
    @Test func `should ask a login for each range once, however many recaps read it`() async {
        let log = Log([day(21, cost: 12)])
        let recaps = recaps([login("a", log)]) { self.date(22) }

        await recaps.readIfStale()

        #expect(log.asked == 6)
    }

    @Test func `should read again when a login's usage was read again`() async {
        let log = Log([day(21, cost: 12)])
        let recaps = recaps([login("a", log)]) { self.date(22) }
        await recaps.readIfStale()

        log.stats.append(day(22, cost: 8))
        log.lastRead = Days(log.stats, knowsCost: true)
        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.total == 20)
    }

    @Test func `should not read again when nothing changed`() async {
        let log = Log([day(21, cost: 12)])
        let recaps = recaps([login("a", log)]) { self.date(22) }
        await recaps.readIfStale()
        let asked = log.asked

        await recaps.readIfStale()

        #expect(log.asked == asked)
        #expect(recaps.recap(for: .this(.week))?.total == 12)
    }

    @Test func `should read again after a read that was cancelled`() async {
        let log = Log([day(21, cost: 12)])
        var cancelNext = true
        let cancelling = RecapLogin(providerId: "a", lastRead: { log.lastRead }) { range in
            if cancelNext { cancelNext = false; withUnsafeCurrentTask { $0?.cancel() } }
            return Days(log.stats.filter { range.contains($0.date, calendar: self.calendar) }, knowsCost: true)
        }
        let recaps = recaps([cancelling]) { self.date(22) }
        await Task { await recaps.readIfStale() }.value
        #expect(recaps.recap(for: .this(.week)) == nil)

        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.total == 12)
    }

    @Test func `should read again when another provider takes a login's place, even with the same days`() async {
        let days = [day(21, cost: 12)]
        var lineup = [login("a", Log(days))]
        let recaps = Recaps(logins: { lineup }, now: { self.date(22) }, calendar: calendar)
        await recaps.readIfStale()

        lineup = [login("b", Log(days))]
        await recaps.readIfStale()

        #expect(recaps.recap(for: .this(.week))?.providers.map(\.provider) == ["b"])
    }

    @Test func `should hand back the recap of the week that closed before its read`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(14, cost: 10)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(of: week(14))?.total == 10)
    }

    /// The week the read was taken in was still under way: its recap is not
    /// the whole week's, and a week the read didn't hold has none.
    @Test func `should hand back no recap of a week the read did not see close`() async {
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(14, cost: 10), day(7, cost: 5)]))]) { self.date(22) }

        await recaps.readIfStale()

        #expect(recaps.recap(of: week(22)) == nil)
        #expect(recaps.recap(of: week(7)) == nil)
    }

    @Test func `should hand back no recap of the week that closed until a read after the turn finishes`() async {
        var today = date(22)
        let recaps = recaps([login("a", Log([day(21, cost: 12), day(22, cost: 3)]))]) { today }
        await recaps.readIfStale()

        today = date(27)
        #expect(recaps.recap(of: week(22)) == nil)

        await recaps.readIfStale()
        #expect(recaps.recap(of: week(22))?.total == 15)
    }

    @Test func `should hold no recap before it is read`() {
        let recaps = recaps([login("a", Log([day(21, cost: 12)]))]) { self.date(22) }

        #expect(recaps.recap(for: .this(.week)) == nil)
    }
}
