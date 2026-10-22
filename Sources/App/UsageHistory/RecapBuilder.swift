import Domain
import Foundation

/// One login, as the recap asks it: its provider, and its days in a range
/// (`UsageHistory.days(in:)`).
struct RecapLogin {
    let providerId: String
    let days: @MainActor (DateRange) async -> Days
}

/// The composition behind the recap card: asks each login for its days in a
/// week and in the week before, by provider, and hands them to `Recap`. It
/// cuts no days and picks no unit — those are `UsageHistory.days(in:)`'s and
/// `Recap`'s.
@MainActor
enum RecapBuilder {
    /// The logins the popover watches that read usage history.
    static func logins(of monitor: QuotaMonitor) -> [RecapLogin] {
        monitor.lineup.compactMap { login in
            login.usageHistory.map { history in
                RecapLogin(providerId: login.providerId) { await history.days(in: $0) }
            }
        }
    }

    /// Both weeks the card offers, each against the week before it.
    static func recaps(of logins: [RecapLogin], at now: Date, calendar: Calendar) async -> [RecapRange: Recap] {
        var recaps: [RecapRange: Recap] = [:]
        for range in RecapRange.allCases {
            let week = range.range(containing: now, calendar: calendar)
            recaps[range] = Recap(this: await days(of: logins, in: week),
                                  before: await days(of: logins, in: week.before(calendar: calendar)))
        }
        return recaps
    }

    /// Each provider's days in `range`; two logins of one provider read as one.
    private static func days(of logins: [RecapLogin], in range: DateRange) async -> [String: Days] {
        var read: [String: [Days]] = [:]
        for login in logins {
            read[login.providerId, default: []].append(await login.days(range))
        }
        return read.mapValues(Days.merged)
    }
}

/// When the page reads the recap again: another week, the card turned on, or
/// a login's days read again.
struct RecapReload: Equatable {
    let week: DateRange
    let isOn: Bool
    let usage: [Days?]
}
