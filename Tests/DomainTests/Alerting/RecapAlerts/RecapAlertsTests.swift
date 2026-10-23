import Foundation
import Mockable
import Testing
@testable import Domain

/// *Recap alerts*: the week turned, the closed week hasn't gone out, and it
/// added up to something — read through `WeeklyRecaps`, marked sent, and told
/// to the recap destinations (docs/features/alerting/recap-alerts/design.md).
@MainActor
@Suite
struct RecapAlertsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday, as this test's person's week starts
        return calendar
    }()

    /// October 2026: Monday the 19th opens the week that holds Thursday the 22nd.
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func day(_ day: Int, cost: Decimal) -> DailyUsageStat {
        DailyUsageStat(date: date(day), totalCost: cost, totalTokens: 10, workingTime: 0, sessionCount: 1)
    }

    /// A login's log, kept in memory: what it last read.
    private final class Log {
        var stats: [DailyUsageStat]
        var lastRead: Days?
        init(_ stats: [DailyUsageStat]) {
            self.stats = stats
            lastRead = Days(stats, knowsCost: true)
        }
    }

    /// A login whose log answers each range with the days that fall in it —
    /// as `UsageHistory.days(in:)` does.
    private func login(_ provider: String, _ log: Log) -> RecapLogin {
        RecapLogin(providerId: provider, lastRead: { log.lastRead }) { range in
            Days(log.stats.filter { range.contains($0.date, calendar: self.calendar) }, knowsCost: true)
        }
    }

    private let told = RecordingRecapDestination()
    private let memory = InMemoryRecapSentRepository()

    private func alerts(_ logins: [RecapLogin], now: @escaping () -> Date,
                        destination: RecordingRecapDestination? = nil) -> RecapAlerts {
        let recaps = WeeklyRecaps(logins: { logins }, now: now, calendar: calendar)
        return RecapAlerts(destination: destination ?? told, recaps: recaps, names: { ["a": "Alpha"] },
                           memory: memory, calendar: calendar, now: now)
    }

    @Test func `should announce the week that closed on the first review of a new week`() async {
        let decider = alerts([login("a", Log([day(14, cost: 10)]))], now: { self.date(22) })

        await decider.review()

        #expect(told.recaps.count == 1)
        #expect(told.recaps.first?.recap.total == 10)
        #expect(told.recaps.first?.week == DateRange(first: date(12), last: date(18), calendar: calendar))
    }

    @Test func `should send once and stay quiet for the rest of the week`() async {
        let decider = alerts([login("a", Log([day(14, cost: 10)]))], now: { self.date(22) })

        await decider.review()
        await decider.review()

        #expect(told.recaps.count == 1)
    }

    @Test func `should mark the week sent even when it added up to nothing`() async {
        // The week that closed holds nothing; its log's usage is all this week.
        let decider = alerts([login("a", Log([day(21, cost: 10)]))], now: { self.date(22) })

        await decider.review()

        #expect(told.recaps.isEmpty)
        #expect(memory.sentAt == date(22))
    }

    @Test func `should wait for a read that finished before marking the week sent`() async {
        let log = Log([day(14, cost: 10)])
        var cancelNext = true
        let cancelling = RecapLogin(providerId: "a", lastRead: { log.lastRead }) { range in
            if cancelNext { cancelNext = false; withUnsafeCurrentTask { $0?.cancel() } }
            return Days(log.stats.filter { range.contains($0.date, calendar: self.calendar) }, knowsCost: true)
        }
        let decider = alerts([cancelling], now: { self.date(22) })

        // The cancelling read runs in its own task, so the cancellation ends
        // with it — as a refresh's observer task would.
        await Task { await decider.review() }.value

        // A read that didn't finish leaves the week unmarked and unannounced.
        #expect(told.recaps.isEmpty)
        #expect(memory.sentAt == nil)

        await decider.review()

        #expect(told.recaps.map(\.recap.total) == [10])
        #expect(memory.sentAt == date(22))
    }

    @Test func `should name each provider as the lineup names it`() async throws {
        let decider = alerts([login("a", Log([day(14, cost: 10)]))], now: { self.date(22) })

        await decider.review()

        let announced = try #require(told.recaps.first)
        let part = try #require(announced.recap.providers.first)
        #expect(announced.name(of: part) == "Alpha")
    }

    @Test func `should read a provider the lineup no longer keeps as its id`() {
        let recap = Recap(this: ["a": Days([day(14, cost: 10)], knowsCost: true)], before: [:])
        let alert = RecapAlert(recap: recap, week: DateRange(first: date(12), last: date(18), calendar: calendar),
                               calendar: calendar, names: ["b": "Beta"])

        #expect(alert.name(of: Recap.Part(provider: "a", value: 10, share: 1)) == "a")
        #expect(alert.name(of: Recap.Part(provider: "b", value: 10, share: 1)) == "Beta")
    }

    /// A refresh is the recap's only moment: the decider follows the Monitor's
    /// refreshes, as every other decider does.
    @Test func `should ask its moment when a login refreshes`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(providerId: "acme", quotas: [], capturedAt: Date()))
        let product = stubbedProduct("acme", probe: probe, settings: MockRepositoryFactory.makeSettingsRepository())
        let monitor = QuotaMonitor(providers: kept([product]))
        let recaps = WeeklyRecaps(monitor: monitor, calendar: calendar)
        let decider = RecapAlerts(destination: told, recaps: recaps, names: { [:] }, memory: memory, calendar: calendar)
        decider.follow(monitor)

        await monitor.refreshAll()

        // A week with no read logins added up to nothing: marked sent, silent.
        #expect(told.recaps.isEmpty)
        #expect(memory.sentAt != nil)
    }
}
