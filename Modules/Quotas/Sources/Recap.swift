import Foundation

/// A RECAP — what a range of days added up to, told as a few highlights: the
/// total, the split by provider, the top model, the biggest day, the cache
/// savings, and the same range before it. A read of a range, never stored;
/// the one read that may sum across logins (CANONICAL §5, `Recap`).
///
/// The unit is the one `Days` already chooses — cost when a login is priced,
/// tokens when it is not — so a view renders what this says and never counts.
public struct Recap: Sendable, Equatable {

    /// One provider's days in the range — the unit the recap adds up. Two
    /// logins of one provider are one span; the recap names providers, never
    /// logins.
    public struct Span: Sendable, Equatable {
        /// The provider's id — a reference, never a name to parse.
        public let provider: String
        public let days: [DailyUsageStat]

        public init(provider: String, days: [DailyUsageStat]) {
            self.provider = provider
            self.days = days
        }
    }

    /// What a range added up to.
    public struct Totals: Sendable, Equatable {
        public let cost: Decimal
        public let tokens: Int
        public let workingTime: TimeInterval
        public let sessions: Int

        public init(cost: Decimal, tokens: Int, workingTime: TimeInterval, sessions: Int) {
            self.cost = cost
            self.tokens = tokens
            self.workingTime = workingTime
            self.sessions = sessions
        }

        /// Whether the range holds nothing — a recap of nothing is not shown,
        /// never shown as zeros.
        public var isEmpty: Bool { tokens == 0 && cost == 0 && workingTime == 0 }
    }

    /// A provider's share of the range, in the unit in force.
    public struct ProviderShare: Sendable, Equatable, Identifiable {
        public let provider: String
        public let cost: Decimal
        public let tokens: Int

        public var id: String { provider }

        public init(provider: String, cost: Decimal, tokens: Int) {
            self.provider = provider
            self.cost = cost
            self.tokens = tokens
        }
    }

    /// The model that spent the most in the range, when a log named one.
    public struct TopModel: Sendable, Equatable {
        public let model: String
        public let cost: Decimal
        public let tokens: Int

        public init(model: String, cost: Decimal, tokens: Int) {
            self.model = model
            self.cost = cost
            self.tokens = tokens
        }

        /// The model's name for a tight row, by the same rule as a day's line.
        public var displayName: String { ModelUsageLine.displayName(model) }
    }

    /// The day that added up to the most, when any day did.
    public struct BiggestDay: Sendable, Equatable {
        public let date: Date
        public let cost: Decimal
        public let tokens: Int

        public init(date: Date, cost: Decimal, tokens: Int) {
            self.date = date
            self.cost = cost
            self.tokens = tokens
        }

        /// "Wednesday, Oct 15".
        public var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    /// What the range added up to.
    public let totals: Totals
    /// The same range before it, for the comparison — `nil` when nothing is
    /// known of it (the range before held nothing).
    public let previous: Totals?
    /// The providers it spans, largest first in the unit in force.
    public let providers: [ProviderShare]
    /// The model that spent the most in the range, when a log named one.
    public let topModel: TopModel?
    /// The day that added up to the most, when any day did.
    public let biggestDay: BiggestDay?
    /// What prompt caching saved across the range.
    public let cacheSavings: Decimal
    /// Whether a day's cost means anything — cost is the unit when it does,
    /// tokens when not.
    public let knowsCost: Bool

    /// Adds the spans up: the total, the split by provider, the top model and
    /// the biggest day in the range, and what caching saved. `previous` are
    /// the same providers' days one period earlier, read for the comparison.
    public init(spans: [Span], previous: [Span] = [], knowsCost: Bool) {
        self.knowsCost = knowsCost

        let days = spans.flatMap(\.days)
        totals = Self.totals(of: days)
        cacheSavings = days.reduce(Decimal.zero) { $0 + $1.cachedSavings }

        let before = Self.totals(of: previous.flatMap(\.days))
        self.previous = before.isEmpty ? nil : before

        providers = Self.providers(of: spans, knowsCost: knowsCost)
        topModel = Self.topModel(of: days, knowsCost: knowsCost)
        biggestDay = Self.biggestDay(of: days, knowsCost: knowsCost)
    }

    /// Whether the range holds nothing — such a recap is not shown, never
    /// shown as zeros.
    public var isEmpty: Bool { totals.isEmpty }

    // MARK: - The comparison

    /// The total in the unit in force.
    public var value: Double { Self.value(of: totals, knowsCost: knowsCost) }

    /// How much the range grew or shrank against the one before, in percent —
    /// `nil` when there is nothing to compare with.
    public var changePercent: Double? {
        guard let previous else { return nil }
        let before = Self.value(of: previous, knowsCost: knowsCost)
        guard before > 0 else { return nil }
        return (value - before) / before * 100
    }

    /// "+12%" · "−8%" — the change against the range before, or `nil`.
    public var formattedChange: String? {
        guard let changePercent else { return nil }
        let sign = changePercent >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.0f", abs(changePercent)))%"
    }

    /// A provider's part of the range, as a share of the total in the unit in
    /// force — 0 when the range holds nothing.
    public func share(of provider: ProviderShare) -> Double {
        let total = value
        guard total > 0 else { return 0 }
        return Self.value(of: provider, knowsCost: knowsCost) / total
    }

    // MARK: - Formatting

    /// "$14.26"
    public var formattedCost: String { MoneyFormat.string(totals.cost) }

    /// "19.5M" · "1.2K" · "500" — every token, cache included.
    public var formattedTokens: String { Self.format(tokens: totals.tokens) }

    /// "22h 16m" · "5m 30s"
    public var formattedWorkingTime: String {
        let hours = Int(totals.workingTime) / 3600
        let minutes = Int(totals.workingTime) / 60 % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(Int(totals.workingTime) % 60)s"
    }

    /// "$412.30"
    public var formattedSavings: String { MoneyFormat.string(cacheSavings) }

    /// "62%" — a provider's share of the range.
    public func formattedShare(of provider: ProviderShare) -> String {
        "\(String(format: "%.0f", share(of: provider) * 100))%"
    }

    // MARK: - The arithmetic

    private static func totals(of days: [DailyUsageStat]) -> Totals {
        Totals(cost: days.reduce(Decimal.zero) { $0 + $1.totalCost },
               tokens: days.reduce(0) { $0 + $1.totalTokensWithCache },
               workingTime: days.reduce(0) { $0 + $1.workingTime },
               sessions: days.reduce(0) { $0 + $1.sessionCount })
    }

    private static func providers(of spans: [Span], knowsCost: Bool) -> [ProviderShare] {
        var byProvider: [String: ProviderShare] = [:]
        for span in spans {
            let cost = span.days.reduce(Decimal.zero) { $0 + $1.totalCost }
            let tokens = span.days.reduce(0) { $0 + $1.totalTokensWithCache }
            if let held = byProvider[span.provider] {
                byProvider[span.provider] = ProviderShare(provider: span.provider,
                                                          cost: held.cost + cost, tokens: held.tokens + tokens)
            } else {
                byProvider[span.provider] = ProviderShare(provider: span.provider, cost: cost, tokens: tokens)
            }
        }
        return byProvider.values.sorted {
            let left = value(of: $0, knowsCost: knowsCost), right = value(of: $1, knowsCost: knowsCost)
            return left == right ? $0.provider < $1.provider : left > right
        }
    }

    private static func topModel(of days: [DailyUsageStat], knowsCost: Bool) -> TopModel? {
        var byModel: [String: TopModel] = [:]
        for line in days.flatMap(\.lines) where !line.model.isEmpty {
            let tokens = line.totalTokens + line.cacheCreationTokens + line.cacheReadTokens
            if let held = byModel[line.model] {
                byModel[line.model] = TopModel(model: line.model, cost: held.cost + line.cost, tokens: held.tokens + tokens)
            } else {
                byModel[line.model] = TopModel(model: line.model, cost: line.cost, tokens: tokens)
            }
        }
        return byModel.values.max {
            let left = value(of: $0, knowsCost: knowsCost), right = value(of: $1, knowsCost: knowsCost)
            return left == right ? $0.model > $1.model : left < right
        }
    }

    private static func biggestDay(of days: [DailyUsageStat], knowsCost: Bool) -> BiggestDay? {
        var byDate: [Date: BiggestDay] = [:]
        for day in days {
            if let held = byDate[day.date] {
                byDate[day.date] = BiggestDay(date: day.date, cost: held.cost + day.totalCost,
                                               tokens: held.tokens + day.totalTokensWithCache)
            } else {
                byDate[day.date] = BiggestDay(date: day.date, cost: day.totalCost, tokens: day.totalTokensWithCache)
            }
        }
        return byDate.values.max {
            let left = value(of: $0, knowsCost: knowsCost), right = value(of: $1, knowsCost: knowsCost)
            return left == right ? $0.date < $1.date : left < right
        }
    }

    private static func value(of totals: Totals, knowsCost: Bool) -> Double {
        knowsCost ? NSDecimalNumber(decimal: totals.cost).doubleValue : Double(totals.tokens)
    }

    private static func value(of provider: ProviderShare, knowsCost: Bool) -> Double {
        knowsCost ? NSDecimalNumber(decimal: provider.cost).doubleValue : Double(provider.tokens)
    }

    private static func value(of model: TopModel, knowsCost: Bool) -> Double {
        knowsCost ? NSDecimalNumber(decimal: model.cost).doubleValue : Double(model.tokens)
    }

    private static func value(of day: BiggestDay, knowsCost: Bool) -> Double {
        knowsCost ? NSDecimalNumber(decimal: day.cost).doubleValue : Double(day.tokens)
    }

    /// "19.5M" · "1.2K" · "500".
    static func format(tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(tokens) / 1_000)
        default: return "\(tokens)"
        }
    }
}