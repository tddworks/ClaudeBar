import Foundation
import Quotas

/// A login as Alerting reaches it (CANONICAL §7): its id, its product's id, the
/// name the lineup prints, and the usage the person sees — hidden quotas already
/// left out. Plain values, so `RuleEngine` needs no `Account`.
public struct RuleLogin: Sendable, Equatable {
    public let id: String
    public let providerId: String
    /// The login as the lineup names it (*Claude · work*).
    public let name: String
    public let usage: UsageSnapshot?

    /// A login as Alerting reaches it: the ids a rule scopes and throttles by,
    /// the lineup name and the usage the person sees.
    public init(id: String, providerId: String, name: String, usage: UsageSnapshot?) {
        self.id = id
        self.providerId = providerId
        self.name = name
        self.usage = usage
    }
}

/// A login's worst quota, as a plain value: the one quota a rule judges, and
/// everything a payload or a log needs to name it.
///
/// The worst leads — the most severe status first, then the lowest share — the
/// way every other surface reads a login. A balance with no ceiling has no share
/// (`Quota.left`), so `percentLeft` is nil for one and a percent condition never
/// holds; it can still be the worst by status, so a *depleted* rule reaches it.
public struct RuleReading: Sendable, Equatable {
    /// The login, as the lineup names it.
    public let login: String
    /// The login's own id, for a throttle that remembers who is in.
    public let loginId: String
    public let providerId: String
    /// The quota window's name (*Session*, *Weekly*, *Balance*).
    public let window: String
    /// What is left, in whole percent, floored; nil when the worst quota has no
    /// share.
    public let percentLeft: Int?
    /// When the window refills, when the provider said.
    public let resetsAt: Date?
    /// The worst quota's status under the person's policy.
    public let status: QuotaStatus

    /// A reading of one login's worst quota, as a plain value.
    public init(
        login: String,
        loginId: String,
        providerId: String,
        window: String,
        percentLeft: Int?,
        resetsAt: Date?,
        status: QuotaStatus
    ) {
        self.login = login
        self.loginId = loginId
        self.providerId = providerId
        self.window = window
        self.percentLeft = percentLeft
        self.resetsAt = resetsAt
        self.status = status
    }

    /// The worst quota in a login's usage, under the person's policy; nil when
    /// the login has no usage or reports no quota.
    public static func worst(of login: RuleLogin, under policy: StatusPolicy) -> RuleReading? {
        guard let usage = login.usage, !usage.quotas.isEmpty else { return nil }
        let worst = usage.quotas.min { isWorse($0, $1, under: policy) }
        guard let quota = worst else { return nil }
        return RuleReading(
            login: login.name,
            loginId: login.id,
            providerId: login.providerId,
            window: quota.quotaType.displayName,
            percentLeft: quota.percentLeft.map { Int($0.rounded(.down)) },
            resetsAt: quota.resetsAt,
            status: quota.status(under: policy)
        )
    }

    /// Whether `a` should come before `b` in the worst-first order: the more
    /// severe status first, then the lower share. A quota with no share ranks
    /// after one that has a share of the same status.
    private static func isWorse(_ a: UsageQuota, _ b: UsageQuota, under policy: StatusPolicy) -> Bool {
        let sa = a.status(under: policy), sb = b.status(under: policy)
        if sa != sb { return sa > sb }
        switch (a.percentLeft, b.percentLeft) {
        case let (a?, b?): return a < b
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return false
        }
    }
}