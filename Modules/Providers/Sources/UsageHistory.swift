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
    public private(set) var lastThirtyDays: Quotas.Days?

    /// Whether a day's cost means anything; without it only tokens do.
    public var knowsCost: Bool { log.knowsCost }

    /// The app this history counts, when it isn't the login's own tool —
    /// another app on this Mac that uses the same plan.
    public let label: String?
    /// Other apps on this Mac that use the same plan, each its own history:
    /// shown under its own name, never added to this one's days.
    public let otherApps: [UsageHistory]
    /// The other apps used today or yesterday — the ones with a card.
    public var usedOtherApps: [UsageHistory] { otherApps.filter { $0.report != nil } }
    /// Whether there is anything to show — this login's days or another app's.
    public var hasUsage: Bool { report != nil || !usedOtherApps.isEmpty }

    private let log: UsageLog
    private let ledger: DayLedger?

    /// - Parameter ledger: where closed days are kept; without one every
    ///   read goes to the logs.
    public init(log: UsageLog, ledger: DayLedger? = nil, label: String? = nil, otherApps: [UsageHistory] = []) {
        self.log = log
        self.ledger = ledger
        self.label = label
        self.otherApps = otherApps
    }

    /// A login's history as its definition says, with one history per other
    /// app — each its own log and, under `ledger("<login>/<label>")`, its own
    /// kept days.
    public convenience init(_ definition: UsageLog.Definition, login: String,
                            log makeLog: (UsageLog.Definition) -> UsageLog,
                            ledger: (String) -> DayLedger? = { _ in nil }) {
        self.init(log: makeLog(definition), ledger: ledger(login), otherApps: (definition.otherApps ?? []).map { app in
            UsageHistory(log: makeLog(app.definition), ledger: ledger("\(login)/\(app.label)"), label: app.label)
        })
    }

    /// One range of dates, every date present. Closed days come from the
    /// ledger; the logs are read only from the first day the ledger doesn't
    /// hold.
    public func days(in range: DateRange) async -> Quotas.Days {
        let knowsCost = log.knowsCost
        guard let ledger else {
            return Quotas.Days(await log.days(in: range), knowsCost: knowsCost)
        }
        let calendar = log.calendar
        let now = log.currentTime
        let kept = ledger.days(readAs: log.fingerprint)
        let dates = range.days(in: calendar)
        guard let firstMissing = dates.first(where: { day in
            !DayLedger.isClosed(day, at: now, calendar: calendar) || kept[DayLedger.name(of: day, calendar: calendar)] == nil
        }) else {
            return Quotas.Days(dates.compactMap { kept[DayLedger.name(of: $0, calendar: calendar)] }, knowsCost: knowsCost)
        }

        let read = await log.days(in: DateRange(first: firstMissing, last: range.last, calendar: calendar))
        var closed: [String: DailyUsageStat] = [:]
        for day in read where DayLedger.isClosed(day.date, at: now, calendar: calendar) {
            closed[DayLedger.name(of: day.date, calendar: calendar)] = day
        }
        ledger.keep(closed, readAs: log.fingerprint)

        let before = dates.prefix { $0 < firstMissing }.compactMap { kept[DayLedger.name(of: $0, calendar: calendar)] }
        return Quotas.Days(before + read, knowsCost: knowsCost)
    }

    /// Reads the logs again: today against yesterday first, for the cards,
    /// then the last thirty days, for the chart — closed days from the
    /// ledger. Days with nothing are kept as none.
    public func read() async {
        for app in otherApps { await app.read() }
        let days = await days(in: .last(2, endingOn: log.currentTime, calendar: log.calendar))
        guard days.stats.count == 2 else { return }
        let report = DailyUsageReport(today: days.stats[1], previous: days.stats[0])
        self.report = report.today.isEmpty && report.previous.isEmpty ? nil : report

        let month = await self.days(in: .last(30, endingOn: log.currentTime, calendar: log.calendar))
        lastThirtyDays = month.stats.allSatisfy(\.isEmpty) ? nil : month
    }
}
