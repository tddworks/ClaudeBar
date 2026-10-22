import Foundation
import Observation

/// *Claude · work Login Expiry — Login expires in 3 days*, as plain values.
public struct LoginExpiryAlert: Sendable, Equatable {
    /// The login, as the lineup names it.
    public let login: String
    /// The product the login belongs to.
    public let providerId: String
    /// Calendar days from today to the expiry — `0` is said as *expires today*.
    public let days: Int

    public init(login: String, providerId: String, days: Int) {
        self.login = login
        self.providerId = providerId
        self.days = days
    }
}

/// What the card shows while an expiry warning is live: how long the
/// sign-in has left.
public struct LoginExpiryWarning: Sendable, Equatable {
    /// Calendar days from today — `0` is today.
    public let days: Int
}

/// The days as a person reads them — *in 3 days*, *tomorrow*, or *today*.
/// One wording for every destination: this Mac's notification, a webhook,
/// the card.
public enum LoginExpiryWords {
    /// The days said aloud; `0` is said as *today*, `1` as *tomorrow*, never
    /// a timestamp dump.
    public static func forDays(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "tomorrow"
        default: "in \(days) days"
        }
    }
}

/// *Login expiry*: a sign-in that ends is a heads-up, not an alarm. After
/// each refresh it warns once per step — 7 days, 3 days, today — and stays
/// quiet between steps, once the sign-in is renewed (a new instant starts a
/// fresh ladder), once it has already expired — the CLI says so itself — and
/// forever about a login whose expiry no data source can read. It follows
/// refreshes through `QuotaMonitor.onRefreshed`, so the Monitor knows
/// nothing of it ([design](docs/features/alerting/login-expiry/design.md)).
@MainActor
@Observable
public final class LoginExpiryAlerts {
    /// The days each step is told at, soonest last.
    private static let steps: [Int] = [7, 3, 0]

    @ObservationIgnored private let destination: any AlertDestination
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Each login's ladder: the sign-in it was told about, and the steps said.
    /// Kept in memory: after a relaunch the current step is told once more.
    @ObservationIgnored private var told: [String: (expiresAt: Date, steps: Set<Int>)] = [:]

    public init(destination: any AlertDestination, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.destination = destination
        self.calendar = calendar
        self.now = now
    }

    /// After a refresh: tells the step `login`'s sign-in has reached, once.
    /// `expiresAt` is what the login's data sources last read — `nil` when
    /// none of them declares an expiry any more, which forgets the ladder.
    public func review(_ login: String, named name: String, provider: String, expiresAt: Date?) async {
        guard let expiresAt else {
            told[login] = nil
            return
        }
        let days = Self.days(from: now(), to: expiresAt, calendar: calendar)
        guard days >= 0 else { return }
        // Before the first step: quiet, and the ladder keeps what it was told —
        // days only ever fall for one sign-in, so a step reached stays reached.
        guard let step = Self.steps.last(where: { days <= $0 }) else { return }
        var ladder = told[login] ?? (expiresAt, [])
        if ladder.expiresAt != expiresAt { ladder = (expiresAt, []) }
        guard !ladder.steps.contains(step) else { return }
        ladder.steps.insert(step)
        told[login] = ladder
        await destination.announce(.loginExpiry(LoginExpiryAlert(login: name, providerId: provider, days: days)))
    }

    /// What the card shows while a warning is live — the same ladder the
    /// telling reads, so *within 7 days* is written once. `nil` when no step
    /// is reached, the sign-in has no knowable expiry, or is already gone.
    public func warning(of login: Account) -> LoginExpiryWarning? {
        guard let expiresAt = login.loginExpiresAt else { return nil }
        let days = Self.days(from: now(), to: expiresAt, calendar: calendar)
        guard days >= 0, Self.steps.contains(where: { days <= $0 }) else { return nil }
        return LoginExpiryWarning(days: days)
    }

    /// Follows every refresh of `monitor`: the login, as the lineup names it,
    /// and what its credentials said at the refresh.
    public func follow(_ monitor: QuotaMonitor) {
        monitor.onRefreshed { [weak monitor] login in
            guard let monitor else { return }
            await self.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                              expiresAt: login.loginExpiresAt)
        }
    }

    /// Calendar days on this Mac from `today` to `expiresAt` — `0` is today,
    /// negative once it is gone. Never a timestamp: the person counts days.
    private static func days(from today: Date, to expiresAt: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: today),
                                to: calendar.startOfDay(for: expiresAt)).day ?? 0
    }
}
