import Domain
import Foundation

/// One login's days, already read — the thirty days the login keeps
/// (`UsageHistory.lastThirtyDays`) — and the provider they belong to.
struct RecapLogin: Equatable {
    let providerId: String
    let days: Days
}

/// Builds the person's recap from every login's days — the one read that
/// spans logins. Pure: the days are already read, the range is picked out of
/// them, and nothing here counts; `Recap` adds up.
enum RecapBuilder {

    /// The recap of `range` across `logins`, with the range before it for the
    /// comparison. Two logins of one provider are added into that provider's
    /// one share. Cost is the unit when any login's days are priced.
    static func build(_ logins: [RecapLogin], in range: DateRange, calendar: Calendar) -> Recap {
        Recap(spans: spans(logins, in: range, calendar: calendar),
              previous: spans(logins, in: range.before(calendar: calendar), calendar: calendar),
              knowsCost: logins.contains { $0.days.knowsCost })
    }

    /// Each login as a span of the days that fall in `range` — a day outside
    /// it belongs to another range, and is left out.
    private static func spans(_ logins: [RecapLogin], in range: DateRange, calendar: Calendar) -> [Recap.Span] {
        logins.map { login in
            Recap.Span(provider: login.providerId,
                       days: login.days.stats.filter { range.contains($0.date, calendar: calendar) })
        }
    }
}