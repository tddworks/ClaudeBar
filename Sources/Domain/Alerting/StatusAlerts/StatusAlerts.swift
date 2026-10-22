import Foundation

/// *Claude · work is critical — was warning*, as plain values.
public struct StatusAlert: Sendable, Equatable {
    /// The login, as the lineup names it.
    public let login: String
    /// The product the login belongs to.
    public let providerId: String
    /// The status it had.
    public let was: QuotaStatus
    /// The status it got worse to.
    public let now: QuotaStatus

    public init(login: String, providerId: String, was: QuotaStatus, now: QuotaStatus) {
        self.login = login
        self.providerId = providerId
        self.was = was
        self.now = now
    }
}

/// *Status alerts*: after each refresh it says once that a login's status got
/// worse under the person's policy — *running low*, *critically low*,
/// *depleted* — and stays quiet while it stays or recovers. It follows
/// refreshes through `QuotaMonitor.onRefreshed`, so the Monitor knows nothing
/// of it ([design](docs/features/alerting/status-alerts/design.md)).
@MainActor
public final class StatusAlerts {
    private let destination: any AlertDestination
    /// Each login's last status. Kept in memory: after a relaunch a login
    /// still critical is told once more.
    private var last: [String: QuotaStatus] = [:]

    public init(destination: any AlertDestination) {
        self.destination = destination
    }

    /// After a refresh: tells when `login`'s status got worse and isn't
    /// healthy. The first status seen is compared with healthy. `status` is
    /// the one the person sees — under the policy, hidden quotas left out;
    /// `nil` (no usage) says nothing.
    public func review(_ login: String, named name: String, provider: String, status: QuotaStatus?) async {
        guard let now = status else { return }
        let was = last[login] ?? .healthy
        last[login] = now
        guard now > was, now != .healthy else { return }
        await destination.announce(.status(StatusAlert(login: name, providerId: provider, was: was, now: now)))
    }

    /// Follows every refresh of `monitor`: the login, as the lineup names it,
    /// and its status as the person sees it.
    public func follow(_ monitor: QuotaMonitor) {
        monitor.onRefreshed { [weak monitor] login in
            guard let monitor else { return }
            await self.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                              status: monitor.status(of: login))
        }
    }
}
