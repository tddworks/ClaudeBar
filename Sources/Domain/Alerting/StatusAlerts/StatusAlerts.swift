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
/// *depleted* — and stays quiet while it stays or recovers. Each status is
/// told once per window: a login that eases and worsens again before its
/// window resets is not told twice. It follows refreshes through
/// `QuotaMonitor.onRefreshed`, so the Monitor knows nothing of it
/// ([design](docs/features/alerting/status-alerts/design.md)).
@MainActor
public final class StatusAlerts {
    /// The worst status a login was told this window, when it was told, and
    /// when the window that set it resets — `nil` while no reset still ahead
    /// is known.
    private struct Told {
        let status: QuotaStatus
        let at: Date
        let forgetsAt: Date?
    }

    private let destination: any AlertDestination
    /// Each login's last status, which the alert words as *was*. Kept in
    /// memory: after a relaunch a login still critical is told once more.
    private var last: [String: QuotaStatus] = [:]
    /// Each login's worst status told this window. Under pace-aware, critical
    /// follows time-to-run-out, so pausing and resuming flips warning ↔
    /// critical; without this every flip back to critical was told (#709).
    private var told: [String: Told] = [:]

    public init(destination: any AlertDestination) {
        self.destination = destination
    }

    /// After a refresh: tells when `login`'s status got worse, isn't healthy
    /// and is worse than any status told this window. The first status seen
    /// is compared with healthy. `status` is the one the person sees — under
    /// the policy, hidden quotas left out; `nil` (no usage) says nothing.
    /// `resetsAt` is when the quota that sets the status resets: what was
    /// told is forgotten once a reset passes after it was told, or — with no
    /// reset time — once the login reads healthy. A reset that had already
    /// passed when the status was told says nothing about this window.
    public func review(_ login: String, named name: String, provider: String, status: QuotaStatus?,
                       resetsAt: Date? = nil, at now: Date = Date()) async {
        guard let current = status else { return }
        let was = last[login] ?? .healthy
        last[login] = current
        if let window = told[login], Self.isOver(window, current: current, resetsAt: resetsAt, at: now) {
            told[login] = nil
        }
        // A login told before its quota had a reset still ahead takes the
        // first one it reports, so the next window can tell it again.
        if let window = told[login], window.forgetsAt == nil, let resetsAt, resetsAt > now {
            told[login] = Told(status: window.status, at: window.at, forgetsAt: resetsAt)
        }
        guard current > was, current > (told[login]?.status ?? .healthy) else { return }
        told[login] = Told(status: current, at: now, forgetsAt: resetsAt.flatMap { $0 > now ? $0 : nil })
        await destination.announce(.status(StatusAlert(login: name, providerId: provider, was: was, now: current)))
    }

    /// A told window ends at its own reset; with none known, at a reported
    /// reset that passed after the status was told, or once the login reads
    /// healthy. A stale reset, already past when told, never ends it, so a
    /// quota that keeps reporting one is not told on every flip.
    private static func isOver(_ window: Told, current: QuotaStatus, resetsAt: Date?, at now: Date) -> Bool {
        if let forgetsAt = window.forgetsAt { return now >= forgetsAt }
        if let resetsAt, resetsAt > window.at, resetsAt <= now { return true }
        return current == .healthy
    }

    /// Follows every refresh of `monitor`: the login, as the lineup names it,
    /// its status as the person sees it, and when the quota setting it resets.
    public func follow(_ monitor: QuotaMonitor) {
        monitor.onRefreshed { [weak monitor] login in
            guard let monitor else { return }
            let usage = monitor.usage(of: login)
            await self.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                              status: monitor.status(of: login),
                              resetsAt: usage?.worstQuota(under: monitor.statusPolicy)?.resetsAt)
        }
    }
}
