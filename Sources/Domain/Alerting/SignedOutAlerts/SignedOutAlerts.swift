import Foundation

/// *Claude · work signed out — Run `claude` in terminal to log in again.*, as
/// plain values: each destination words it.
public struct SignedOutAlert: Sendable, Equatable {
    /// The login, as the lineup names it.
    public let login: String
    /// The product the login belongs to.
    public let providerId: String
    /// What to do, in the definition's words; `nil` when it gives none.
    public let hint: String?

    public init(login: String, providerId: String, hint: String?) {
        self.login = login
        self.providerId = providerId
        self.hint = hint
    }
}

/// *Signed out*: a login whose refresh failed because its sign-in ended
/// (`sessionExpired`) is told once, and told again only after a refresh with
/// no error in between. It reads the error the login kept — the one its card
/// shows — never a credential. It follows refreshes, failed ones too, through
/// `QuotaMonitor.onRefreshed` and `onRefreshFailed`, so the Monitor knows
/// nothing of it ([design](docs/features/alerting/signed-out/design.md)).
@MainActor
public final class SignedOutAlerts {
    private let destination: any AlertDestination
    /// The logins told about their sign-out. Kept in memory: after a relaunch
    /// a login still signed out is told once more.
    private var told: Set<String> = []

    public init(destination: any AlertDestination) {
        self.destination = destination
    }

    /// After a refresh: tells once when `login`'s last error says its sign-in
    /// ended. No error forgets it; any other error keeps what was told.
    public func review(_ login: String, named name: String, provider: String, lastError: Error?) async {
        guard let lastError else {
            told.remove(login)
            return
        }
        guard case .sessionExpired(let hint)? = lastError as? UsageError,
              told.insert(login).inserted else { return }
        await destination.announce(.signedOut(SignedOutAlert(login: name, providerId: provider, hint: hint)))
    }

    /// Follows every refresh of `monitor`, succeeded or failed: the login, as
    /// the lineup names it, and the error it kept.
    public func follow(_ monitor: QuotaMonitor) {
        let review: @MainActor (Account) async -> Void = { [weak monitor] login in
            guard let monitor else { return }
            await self.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                              lastError: login.lastError)
        }
        monitor.onRefreshed(review)
        monitor.onRefreshFailed(review)
    }
}
