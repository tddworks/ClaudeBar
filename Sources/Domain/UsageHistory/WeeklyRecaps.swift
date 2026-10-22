import Foundation
import Observation

/// One login, as the recap asks it: its provider, the days it last read
/// (`UsageHistory.lastThirtyDays`, which changes when its usage does), and its
/// days in a range (`UsageHistory.days(in:)`).
public struct RecapLogin {
    public let providerId: String
    public let lastRead: @MainActor () -> Days?
    public let days: @MainActor (DateRange) async -> Days

    public init(providerId: String,
                lastRead: @escaping @MainActor () -> Days?,
                days: @escaping @MainActor (DateRange) async -> Days) {
        self.providerId = providerId
        self.lastRead = lastRead
        self.days = days
    }
}

/// *WEEKLY RECAP*'s two weeks across the lineup: for each `RecapRange`, every
/// login's days in the week and the week before, by provider — two logins of
/// one provider as one (`Days.merged`) — read into a `Recap`. It decides for
/// itself when it is stale: another week than the one it was read for, or a
/// login whose days were read again. It cuts no days and picks no unit — those
/// are `UsageHistory.days(in:)`'s and `Recap`'s.
@MainActor
@Observable
public final class WeeklyRecaps {
    /// Each week's recap, once read.
    public private(set) var recaps: [RecapRange: Recap] = [:]

    /// What the recaps were read for: the week, and each login's last read.
    private struct Reading: Equatable {
        let week: DateRange
        let providers: [String]
        let usage: [Days?]
    }

    /// What `recaps` were read from, and the read under way, if any.
    @ObservationIgnored private var shown: Reading?
    @ObservationIgnored private var underWay: Reading?
    @ObservationIgnored private let logins: @MainActor () -> [RecapLogin]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// - Parameters:
    ///   - logins: the lineup's logins that read usage history, asked at each read.
    ///   - now: the clock.
    ///   - calendar: the person's calendar (`DataSources.calendar()`).
    public init(logins: @escaping @MainActor () -> [RecapLogin],
                now: @escaping () -> Date = Date.init,
                calendar: Calendar) {
        self.logins = logins
        self.now = now
        self.calendar = calendar
    }

    /// The recap over the monitor's lineup: each login that reads usage history.
    public convenience init(monitor: QuotaMonitor, now: @escaping () -> Date = Date.init, calendar: Calendar) {
        self.init(logins: { [weak monitor] in
            (monitor?.lineup ?? []).compactMap { login in
                login.usageHistory.map { history in
                    RecapLogin(providerId: login.providerId,
                               lastRead: { history.lastThirtyDays },
                               days: { await history.days(in: $0) })
                }
            }
        }, now: now, calendar: calendar)
    }

    /// The recap of `range`, once read.
    public func recap(for range: RecapRange) -> Recap? { recaps[range] }

    /// Reads both weeks again when the week turned or a login's days were read
    /// again since the last read; otherwise reads nothing.
    public func readIfStale() async {
        let logins = logins()
        let date = now()
        let current = Reading(week: DateRange.week(containing: date, calendar: calendar),
                              providers: logins.map(\.providerId),
                              usage: logins.map { $0.lastRead() })
        guard current != shown, current != underWay else { return }
        underWay = current

        var read: [RecapRange: Recap] = [:]
        for range in RecapRange.allCases {
            let week = range.range(containing: date, calendar: calendar)
            read[range] = Recap(this: await days(of: logins, in: week),
                                before: await days(of: logins, in: week.before(calendar: calendar)))
        }
        // A newer read started meanwhile: its recaps are the ones to keep.
        guard underWay == current else { return }
        underWay = nil
        // A cancelled read may have stopped short: it is read again next time.
        guard !Task.isCancelled else { return }
        recaps = read
        shown = current
    }

    /// Each provider's days in `range`; two logins of one provider read as one.
    private func days(of logins: [RecapLogin], in range: DateRange) async -> [String: Days] {
        var read: [String: [Days]] = [:]
        for login in logins {
            read[login.providerId, default: []].append(await login.days(range))
        }
        return read.mapValues(Days.merged)
    }
}
