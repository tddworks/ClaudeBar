import Domain
import Foundation

/// One login's days in a recap's range — the days, already read, and the
/// provider they belong to.
struct RecapLogin: Equatable {
    let providerId: String
    let days: Days
}

/// Builds the person's recap from every login's days — the one read that
/// spans logins. `build` is pure: it takes days already read, adds them up
/// through `Recap`, and decides nothing about where they came from. `read`
/// is the App's part: it gathers each login's days for the range and for the
/// range before it, through the login's own `usageHistory`.
enum RecapBuilder {

    /// The recap of `logins`' days, with `previous`' days for the comparison.
    /// Two logins of one provider are added into that provider's one share.
    static func build(_ logins: [RecapLogin], previous: [RecapLogin], knowsCost: Bool) -> Recap {
        Recap(spans: logins.map { Recap.Span(provider: $0.providerId, days: $0.days.stats) },
              previous: previous.map { Recap.Span(provider: $0.providerId, days: $0.days.stats) },
              knowsCost: knowsCost)
    }

    /// The recap of `range` across `logins`, and the range before it. Each
    /// login's days come from its own `usageHistory`; a login with none is
    /// left out. Cost is the unit when any login is priced.
    @MainActor
    static func read(_ logins: [Account], in range: DateRange, calendar: Calendar) async -> Recap {
        let before = range.before(calendar: calendar)
        var current: [RecapLogin] = []
        var previous: [RecapLogin] = []
        for login in logins {
            guard let history = login.usageHistory else { continue }
            current.append(RecapLogin(providerId: login.providerId, days: await history.days(in: range)))
            previous.append(RecapLogin(providerId: login.providerId, days: await history.days(in: before)))
        }
        let knowsCost = logins.contains { $0.usageHistory?.knowsCost == true }
        return build(current, previous: previous, knowsCost: knowsCost)
    }
}