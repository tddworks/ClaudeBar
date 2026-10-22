import Foundation
import Quotas

/// THE JSON CONTRACT — what the local API and its MCP tools answer with.
/// One word per question, the same nouns the screens print. Every payload is
/// built purely from `Quotas` values, so the whole contract is testable
/// without a Monitor. A `null` means what it means on screen: a balance with
/// no ceiling has no percentage, a quota with no pace has no forecast.
extension QuotaStatus {
    /// The word every surface prints for a status (HEALTHY · WARNING · …).
    var apiName: String {
        switch self {
        case .healthy: "healthy"
        case .warning: "warning"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }
}

/// `GET /status` — the one line: the worst quota across the watched logins,
/// and the overall status under the person's policy.
public struct StatusSummary: Codable, Equatable, Sendable {
    public let status: String
    public let summary: String
    public let lowest: LowestQuota?
    public let providers: Int
    public let updatedAt: String

    /// Builds the line. `lowest` names the login and quota with the least
    /// share left, when any quota has a share at all.
    public init(status: QuotaStatus, lowest: LowestQuota?, providers: Int, at now: Date = Date()) {
        self.status = status.apiName
        if let lowest {
            self.summary = "\(Int(lowest.percentLeft))% left · \(status.apiName)"
        } else {
            self.summary = status.apiName
        }
        self.lowest = lowest
        self.providers = providers
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// The quota about to run out first — what "will I run out?" points at.
public struct LowestQuota: Codable, Equatable, Sendable {
    public let provider: String
    public let login: String
    public let name: String
    public let quota: String
    public let key: String
    public let percentLeft: Double
    public let resetsAt: String?
    public let resetsInMinutes: Int?

    /// Builds one from a quota and the login it belongs to. A quota with no
    /// share (a balance with no ceiling) never stands for the lowest — ask
    /// `LocalAPIRouter.share(of:)`'s rule first.
    public init(quota: UsageQuota, provider: String, login: String, name: String, at now: Date = Date()) {
        self.provider = provider
        self.login = login
        self.name = name
        self.quota = quota.quotaType.displayName
        self.key = quota.quotaType.quotaKey
        // The reading only builds a lowest from a quota that has a share; the
        // zero is unreachable — a balance with no ceiling never stands here.
        self.percentLeft = LocalAPIContract.share(of: quota) ?? 0
        self.resetsAt = quota.resetsAt.map { ISO8601DateFormatter().string(from: $0) }
        self.resetsInMinutes = quota.timeUntilReset.map { Int(($0 / 60).rounded()) }
    }
}

/// `GET /providers` — every watched login: what it last said, its status
/// under the policy, which login has the most left (`best`), which one new
/// terminal sessions start with (`inUse`).
public struct ProvidersReport: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let providers: [ProviderReport]

    public init(providers: [ProviderReport], at now: Date = Date()) {
        self.providers = providers
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// The product, with its logins in the lineup's order.
public struct ProviderReport: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let logins: [LoginReport]

    public init(id: String, name: String, logins: [LoginReport]) {
        self.id = id
        self.name = name
        self.logins = logins
    }
}

/// One login — a row of the Accounts card, as JSON.
public struct LoginReport: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    /// The unpaused login with the most left — *switch to work*.
    public let best: Bool
    /// New terminal sessions start here.
    public let inUse: Bool
    public let plan: String?
    /// *via RPC* — which data source answered, so a fallback is never silent.
    public let source: String?
    public let updatedAt: String?
    public let quotas: [QuotaReport]

    public init(
        id: String, name: String, status: QuotaStatus, best: Bool, inUse: Bool,
        plan: String?, source: String?, updatedAt: Date?, quotas: [QuotaReport], at now: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.status = status.apiName
        self.best = best
        self.inUse = inUse
        self.plan = plan
        self.source = source
        self.updatedAt = updatedAt.map { ISO8601DateFormatter().string(from: $0) }
        self.quotas = quotas
    }
}

/// One limit the vendor set: what is left (a share, or money), and when it
/// refills. A balance with no ceiling reports `percentLeft: null` — writing
/// 100% is the lie the status would believe.
public struct QuotaReport: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let percentLeft: Double?
    public let dollarRemaining: Double?
    public let dollarCap: Double?
    public let currency: String?
    public let resetsAt: String?
    public let resetsInMinutes: Int?

    public init(quota: UsageQuota, at now: Date = Date()) {
        self.key = quota.quotaType.quotaKey
        self.name = quota.compactTitle ?? quota.quotaType.displayName
        self.percentLeft = LocalAPIContract.share(of: quota)
        if case let .money(remaining, of: cap) = quota.left {
            self.dollarRemaining = NSDecimalNumber(decimal: remaining.amount).doubleValue
            self.dollarCap = cap.map { NSDecimalNumber(decimal: $0.amount).doubleValue }
            self.currency = remaining.currency
        } else {
            self.dollarRemaining = nil
            self.dollarCap = nil
            self.currency = nil
        }
        self.resetsAt = quota.resetsAt.map { ISO8601DateFormatter().string(from: $0) }
        self.resetsInMinutes = quota.timeUntilReset.map { Int(($0 / 60).rounded()) }
    }
}

/// `GET /forecast` — every quota that has a forecast line, the card's
/// hourglass row as data. Quotas without a forecast are left out, as their
/// cards leave the line out.
public struct ForecastReport: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let forecasts: [ForecastLine]

    public init(forecasts: [ForecastLine], at now: Date = Date()) {
        self.forecasts = forecasts
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// One quota's answer to *will it last until it resets?*
public struct ForecastLine: Codable, Equatable, Sendable {
    /// `lastsUntilReset` or `runsOut`.
    public let state: String
    public let provider: String
    public let login: String
    public let loginName: String
    public let quota: String
    public let key: String
    /// Present when `state` is `runsOut`.
    public let runsOutInMinutes: Int?
    /// Present when `state` is `runsOut`: how long before the window refills.
    public let beforeResetMinutes: Int?

    /// Builds one from a quota's forecast; `nil` when the quota has none (no
    /// rate, a balance with no ceiling, or already used up) — the card prints
    /// no line and neither does the API.
    public init?(forecast: Forecast, quota: UsageQuota, provider: String, login: String, loginName: String) {
        self.provider = provider
        self.login = login
        self.loginName = loginName
        self.quota = quota.quotaType.displayName
        self.key = quota.quotaType.quotaKey
        switch forecast {
        case .lastsUntilReset:
            self.state = "lastsUntilReset"
            self.runsOutInMinutes = nil
            self.beforeResetMinutes = nil
        case let .runsOut(in: runsOut, beforeReset: beforeReset):
            self.state = "runsOut"
            self.runsOutInMinutes = Self.minutes(runsOut)
            self.beforeResetMinutes = Self.minutes(beforeReset)
        }
    }

    /// The duration as whole minutes, the way the card reads its hourglass.
    private static func minutes(_ duration: Duration) -> Int {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return Int((seconds / 60).rounded())
    }
}

/// `GET /usage/days?n=30` — per login, day by day, every date of the range
/// present: a day with nothing is an empty day, not a missing one.
public struct UsageDaysReport: Codable, Equatable, Sendable {
    public let days: Int
    public let logins: [LoginDays]

    public init(days: Int, logins: [LoginDays]) {
        self.days = days
        self.logins = logins
    }
}

/// One login's series of days.
public struct LoginDays: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let days: [DayUsage]

    public init(id: String, name: String, days: [DayUsage]) {
        self.id = id
        self.name = name
        self.days = days
    }
}

/// One day — what the popover's chart row holds, as data. `cost` is present
/// only when the login's log price their records; a log that writes zero
/// everywhere has nothing to say in dollars.
public struct DayUsage: Codable, Equatable, Sendable {
    public let date: String
    public let cost: Double?
    public let tokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheTokens: Int
    public let workingMinutes: Int
    public let sessions: Int

    /// Builds one from a day's stat. `calendar` formats the date the way the
    /// login's own history counts days.
    public init(stat: DailyUsageStat, knowsCost: Bool, calendar: Calendar) {
        let day = calendar.dateComponents([.year, .month, .day], from: stat.date)
        self.date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        self.cost = knowsCost ? NSDecimalNumber(decimal: stat.totalCost).doubleValue : nil
        self.tokens = stat.totalTokens
        self.inputTokens = stat.inputTokens
        self.outputTokens = stat.outputTokens
        self.cacheTokens = stat.cacheCreationTokens + stat.cacheReadTokens
        self.workingMinutes = Int((stat.workingTime / 60).rounded())
        self.sessions = stat.sessionCount
    }
}

/// The one rule both status and /providers read: the share a quota's `left`
/// holds, or none. A balance with no ceiling has NO percentage (CANONICAL §5);
/// a capped money quota's share is its money's.
public enum LocalAPIContract {
    /// The quota's share left, or `nil` — a balance with no ceiling has none.
    public static func share(of quota: UsageQuota) -> Double? {
        share(of: quota.left)
    }

    /// Whether the quota has a share at all — the balance with no ceiling is
    /// never judged and never stands for the lowest.
    public static func hasShare(_ quota: UsageQuota) -> Bool {
        share(of: quota.left) != nil
    }

    /// The share a `Left` holds: its percent, or its money's — never invented.
    public static func share(of left: Left) -> Double? {
        switch left {
        case let .share(percent):
            return min(100, max(0, percent))
        case let .money(remaining, of: ceiling):
            guard let ceiling, ceiling.amount > 0 else { return nil }
            let left = NSDecimalNumber(decimal: remaining.amount).doubleValue
            let cap = NSDecimalNumber(decimal: ceiling.amount).doubleValue
            return min(100, max(0, left / cap * 100))
        }
    }
}
