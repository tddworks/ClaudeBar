import Foundation
import Quotas

/// THE POOL — a product's logins as one sum of shares: *340% left across
/// 3 logins*. The person with several logins asks for the family's room, not
/// each login's; the pool is that total, made of facts the app already has.
///
/// The law that keeps it honest (docs/features/providers/quota-pools/design.md,
/// [CANONICAL §5](docs/architecture/CANONICAL_MODEL.md)): **a pool is a sum of
/// shares** — over 100 is fine and meaningful, because the logins refill
/// independently and each share is a fact about its own login. It is never a
/// forecast and never a percentage of anything bigger: there is no whole
/// behind it, not the plan, not a budget, not the family of products.
public struct Pool: Sendable, Equatable {
    /// One counted login's room.
    public struct Share: Sendable, Equatable {
        /// The login that brings it, by its lineup id (`<provider>`,
        /// `<provider>.<acct>`).
        public let loginId: String
        /// The share left, in percent — the login's tightest window's, the
        /// number its card leads with (`Account.percentLeft`).
        public let percent: Double

        public init(loginId: String, percent: Double) {
            self.loginId = loginId
            self.percent = percent
        }
    }

    /// The shares, one per counted login, in the person's login order.
    public let shares: [Share]

    /// A pool from these shares — `nil` below two: one login's room is that
    /// login's card, not a pool.
    public init?(shares: [Share]) {
        guard shares.count > 1 else { return nil }
        self.shares = shares
    }

    /// THE SUM — over 100 is fine and meaningful: three logins at 90% make
    /// 270% of one window. Never rounded, never capped, never read as a
    /// percentage of anything bigger.
    public var percent: Double {
        shares.reduce(0) { $0 + $1.percent }
    }

    /// How many logins the sum spans — the sum's own count, never the page's.
    public var count: Int {
        shares.count
    }
}

extension Accounts {
    /// THE POOL — the logins' room, summed: *how much do we have left,
    /// together?* A derived read beside `status` · `best` · `cause`, and the
    /// one place the sum is made.
    ///
    /// Each unpaused login brings the share it already shows — its
    /// `percentLeft`, the number its card leads with. A paused login is out
    /// of every judgement, so it brings nothing; a login with no usage yet,
    /// or one that shows only a balance with no ceiling, brings nothing
    /// either — a share that isn't known is never guessed at zero or at a
    /// hundred. `nil` below two shares (`Pool` keeps that law).
    public var pool: Pool? {
        Pool(shares: unpaused.compactMap { login in
            login.percentLeft.map { Pool.Share(loginId: login.id, percent: $0) }
        })
    }
}
