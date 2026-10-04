import DataSources
import Foundation
import Observation
import Quotas

/// *TODAY'S USAGE* — what one login used, day by day, read from its tool's
/// own logs on this Mac. Not a meter: nothing is left or judged, and the
/// monitor never refreshes it; it is read when the popover opens. The login
/// owns it, as `account.usageHistory` (CANONICAL §2.1); how the days are
/// extracted is its provider's `usageHistory`, run as a `UsageLog`.
@MainActor
@Observable
public final class UsageHistory {
    /// Today's and yesterday's usage, once read and when either holds any.
    public private(set) var report: DailyUsageReport?
    /// *DAILY USAGE — LAST 30 DAYS*: the thirty days ending today, oldest
    /// first, once read and when any of them holds usage.
    public private(set) var lastThirtyDays: [DailyUsageStat] = []

    /// Whether a day's cost means anything; without it only tokens do.
    public var knowsCost: Bool { log.knowsCost }

    private let log: UsageLog
    private let ledger: DayLedger?

    /// - Parameter ledger: where closed days are kept; without one every
    ///   read goes to the logs.
    public init(log: UsageLog, ledger: DayLedger? = nil) {
        self.log = log
        self.ledger = ledger
    }

    /// One day per date of `range`, every date present. Closed days come
    /// from the ledger; the logs are read only from the first day the
    /// ledger doesn't hold.
    public func days(in range: DateRange) async -> [DailyUsageStat] {
        guard let ledger else { return await log.days(in: range) }
        let calendar = log.calendar
        let now = log.currentTime
        let kept = ledger.days(readAs: log.fingerprint)
        let dates = range.days(in: calendar)
        guard let firstMissing = dates.first(where: { day in
            !DayLedger.isClosed(day, at: now, calendar: calendar) || kept[DayLedger.name(of: day, calendar: calendar)] == nil
        }) else {
            return dates.compactMap { kept[DayLedger.name(of: $0, calendar: calendar)] }
        }

        let read = await log.days(in: DateRange(first: firstMissing, last: range.last, calendar: calendar))
        var closed: [String: DailyUsageStat] = [:]
        for day in read where DayLedger.isClosed(day.date, at: now, calendar: calendar) {
            closed[DayLedger.name(of: day.date, calendar: calendar)] = day
        }
        ledger.keep(closed, readAs: log.fingerprint)

        let before = dates.prefix { $0 < firstMissing }.compactMap { kept[DayLedger.name(of: $0, calendar: calendar)] }
        return before + read
    }

    /// Reads the logs again: today against yesterday first, for the cards,
    /// then the last thirty days, for the chart — closed days from the
    /// ledger. Days with nothing are kept as none.
    public func read() async {
        let days = await days(in: .last(2, endingOn: log.currentTime, calendar: log.calendar))
        guard days.count == 2 else { return }
        let report = DailyUsageReport(today: days[1], previous: days[0])
        self.report = report.today.isEmpty && report.previous.isEmpty ? nil : report

        let month = await self.days(in: .last(30, endingOn: log.currentTime, calendar: log.calendar))
        lastThirtyDays = month.allSatisfy(\.isEmpty) ? [] : month
    }
}
