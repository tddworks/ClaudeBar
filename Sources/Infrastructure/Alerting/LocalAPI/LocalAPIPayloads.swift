import Foundation
import Domain

/// THE JSON CONTRACT — what the local API and its MCP tools answer with.
/// One word per question, the same nouns the screens print. Every payload
/// encodes an `Overview` — the *All* page's read — and decides nothing, so
/// the whole contract is testable on a hand-built one. A `null` means what it
/// means on screen: a balance with no ceiling has no percentage, a quota with
/// no pace has no forecast, a login with no numbers yet has no status.
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

/// `GET /status` — the one line: the quota the *All* page leads with, and
/// the overall status under the person's policy.
public struct StatusSummary: Codable, Equatable, Sendable {
    /// The worst product's status; `null` while no login has numbers.
    public let status: String?
    public let summary: String
    public let lowest: LowestQuota?
    /// How many products the answer covers — products, never logins.
    public let providers: Int
    public let updatedAt: String

    /// The Overview's line: its status, its leading card's ring and the login
    /// that ring reads, and its cards counted.
    public init(_ overview: Overview, at now: Date = Date()) {
        var lowest: LowestQuota?
        if let card = overview.tightestCard, let login = card.login, let quota = card.tightest {
            lowest = LowestQuota(quota: quota, provider: card.id, login: login.id, name: login.name, at: now)
        }
        self.init(status: overview.status, lowest: lowest, providers: overview.cards.count, at: now)
    }

    /// Builds the line from its parts.
    init(status: QuotaStatus?, lowest: LowestQuota?, providers: Int, at now: Date = Date()) {
        let word = status?.apiName ?? "no usage yet"
        self.status = status?.apiName
        if let percent = lowest?.percentLeft {
            self.summary = "\(Int(percent))% left · \(word)"
        } else {
            self.summary = word
        }
        self.lowest = lowest
        self.providers = providers
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// The quota the *All* page leads with — what "will I run out?" points at.
public struct LowestQuota: Codable, Equatable, Sendable {
    /// The product's id.
    public let provider: String
    public let login: String
    public let name: String
    public let quota: String
    public let key: String
    /// `null` for a balance with no ceiling, which has no percentage.
    public let percentLeft: Double?
    public let resetsAt: String?
    public let resetsInMinutes: Int?

    /// Builds one from a quota and the login it belongs to.
    public init(quota: UsageQuota, provider: String, login: String, name: String, at now: Date = Date()) {
        self.provider = provider
        self.login = login
        self.name = name
        self.quota = quota.quotaType.displayName
        self.key = quota.quotaType.quotaKey
        self.percentLeft = quota.percentLeft
        self.resetsAt = quota.resetsAt.map { ISO8601DateFormatter().string(from: $0) }
        self.resetsInMinutes = quota.timeUntilReset.map { Int(($0 / 60).rounded()) }
    }
}

/// `GET /providers` — every card's logins: what each last said, its status
/// under the policy, which login has the most left (`best`), which one new
/// terminal sessions start with (`inUse`).
public struct ProvidersReport: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let providers: [ProviderReport]

    /// The Overview's cards, one product each, in pill order.
    public init(_ overview: Overview, at now: Date = Date()) {
        self.init(providers: overview.cards.map { card in
            ProviderReport(id: card.id, name: card.name, logins: card.logins.map { LoginReport($0, of: card, at: now) })
        }, at: now)
    }

    public init(providers: [ProviderReport], at now: Date = Date()) {
        self.providers = providers
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// The product, with its logins in the person's order.
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
    /// `null` while the login has no numbers — never *healthy* by default.
    public let status: String?
    /// The unpaused login with the most left — *switch to work*.
    public let best: Bool
    /// New terminal sessions start here.
    public let inUse: Bool
    public let plan: String?
    /// *via RPC* — which data source answered, so a fallback is never silent.
    public let source: String?
    public let updatedAt: String?
    public let quotas: [QuotaReport]

    /// One login of a card, `best` and `inUse` as its product answered.
    public init(_ login: OverviewCard.Login, of card: OverviewCard, at now: Date = Date()) {
        self.init(
            id: login.id, name: login.name, status: login.status,
            best: card.best == login.id, inUse: card.inUse == login.id,
            plan: login.snapshot?.accountTier?.badgeText, source: login.source,
            updatedAt: login.snapshot?.capturedAt,
            quotas: (login.snapshot?.quotas ?? []).map { QuotaReport(quota: $0, at: now) }, at: now
        )
    }

    public init(
        id: String, name: String, status: QuotaStatus?, best: Bool, inUse: Bool,
        plan: String?, source: String?, updatedAt: Date?, quotas: [QuotaReport], at now: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.status = status?.apiName
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
/// 100% is the lie the status would believe. The share is the quota's own
/// (`UsageQuota.percentLeft`), never worked out here.
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
        self.percentLeft = quota.percentLeft
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

    /// Every card login's quotas that have a forecast line, in pill order.
    public init(_ overview: Overview, at now: Date = Date()) {
        self.init(forecasts: overview.cards.flatMap { card in
            card.logins.flatMap { login in
                (login.snapshot?.quotas ?? []).compactMap { quota in
                    quota.forecast.flatMap {
                        ForecastLine(forecast: $0, quota: quota, provider: card.id, login: login.id, loginName: login.name)
                    }
                }
            }
        }, at: now)
    }

    public init(forecasts: [ForecastLine], at now: Date = Date()) {
        self.forecasts = forecasts
        self.updatedAt = ISO8601DateFormatter().string(from: now)
    }
}

/// One quota's answer to *will it last until it resets?*
public struct ForecastLine: Codable, Equatable, Sendable {
    /// `lastsUntilReset` or `runsOut`.
    public let state: String
    /// The product's id.
    public let provider: String
    public let login: String
    public let loginName: String
    public let quota: String
    public let key: String
    /// Present when `state` is `runsOut`.
    public let runsOutInMinutes: Int?
    /// Present when `state` is `runsOut`: how long before the window refills.
    public let beforeResetMinutes: Int?

    /// Builds one from a quota's forecast.
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
    public let logins: [LoginDaySeries]

    public init(days: Int, logins: [LoginDaySeries]) {
        self.days = days
        self.logins = logins
    }

    /// Each card login's last `count` days, read from its own history on the
    /// ask — like a popover opening, never in the background. A login whose
    /// provider declares no history has no series.
    public static func read(_ overview: Overview, count: Int, endingOn now: Date = Date(),
                            calendar: Calendar = DataSources.calendar()) async -> UsageDaysReport {
        var series: [LoginDaySeries] = []
        for login in overview.cards.flatMap(\.logins) {
            guard let history = login.usageHistory else { continue }
            let days = await history.days(in: .last(count, endingOn: now, calendar: calendar))
            series.append(LoginDaySeries(
                id: login.id, name: login.name,
                days: days.stats.map { DayUsage(stat: $0, knowsCost: days.knowsCost, calendar: calendar) }
            ))
        }
        return UsageDaysReport(days: count, logins: series)
    }
}

/// One login's series of days.
public struct LoginDaySeries: Codable, Equatable, Sendable {
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
