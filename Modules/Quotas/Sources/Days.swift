import Foundation

/// A RANGE OF DAYS — the one answer `UsageHistory.days(in:)` returns, and
/// every view's questions answered: which models, in order; a day's lines,
/// largest first; its total in a unit; the mix, largest first; a day's value
/// and its shade; what the cache saved. A view renders what this says and
/// never counts for itself (CANONICAL §5, `Days`).
public struct Days: Sendable, Equatable {
    /// Every date of the range, empty days included.
    public let stats: [DailyUsageStat]
    /// Whether a day's cost means anything — cost is the unit when it does,
    /// tokens when not.
    public let knowsCost: Bool

    public init(_ stats: [DailyUsageStat], knowsCost: Bool) {
        self.stats = stats
        self.knowsCost = knowsCost
    }

    /// What a range of days is read in — a day's value, a total, the mix.
    /// Working time is a unit a range can be totalled in; it has no per-model
    /// split, so the mix is only ever cost or tokens.
    public enum Unit: Sendable, Equatable, CaseIterable {
        case cost
        case tokens
        case workingTime
    }

    /// The unit in force: cost when a day's cost means anything, tokens when not.
    public var unit: Unit { knowsCost ? .cost : .tokens }

    /// The models the days name, in name order — a model keeps its colour
    /// from day to day. The unnamed line is not a model.
    public var models: [String] {
        Set(stats.flatMap { $0.lines.map(\.model) }).filter { !$0.isEmpty }.sorted()
    }

    /// Whether a model split is offered — whether any day names a model.
    public var hasModels: Bool {
        stats.contains { $0.lines.contains { !$0.model.isEmpty } }
    }

    /// A day's lines, largest part first in the unit in force — the unnamed
    /// line among them, so they add up to the day.
    public func lines(of day: DailyUsageStat) -> [ModelUsageLine] {
        day.lines.sorted { value(of: $0) > value(of: $1) }
    }

    /// A day's total in the unit in force.
    public func value(of day: DailyUsageStat) -> Double {
        value(of: day, in: unit)
    }

    /// A day's total in a unit.
    public func value(of day: DailyUsageStat, in unit: Unit) -> Double {
        switch unit {
        case .cost: NSDecimalNumber(decimal: day.totalCost).doubleValue
        case .tokens: Double(day.totalTokens)
        case .workingTime: day.workingTime
        }
    }

    /// The range's total in the unit in force.
    public var total: Double {
        total(in: unit)
    }

    /// The range's total in a unit — cost, tokens or working time.
    public func total(in unit: Unit) -> Double {
        stats.reduce(0) { $0 + value(of: $1, in: unit) }
    }

    /// A line's part in the unit in force.
    public func value(of line: ModelUsageLine) -> Double {
        knowsCost ? NSDecimalNumber(decimal: line.cost).doubleValue : Double(line.totalTokens)
    }

    /// The mix: one line per model, summed over the range, largest first in the
    /// unit in force — the unnamed line among them, so they add up to the range
    /// as a day's lines add up to the day.
    public var byModel: [ModelUsageLine] {
        var totals: [String: ModelUsageLine] = [:]
        for day in stats {
            for line in day.lines {
                let running = totals[line.model]
                totals[line.model] = ModelUsageLine(
                    model: line.model,
                    inputTokens: (running?.inputTokens ?? 0) + line.inputTokens,
                    outputTokens: (running?.outputTokens ?? 0) + line.outputTokens,
                    cacheCreationTokens: (running?.cacheCreationTokens ?? 0) + line.cacheCreationTokens,
                    cacheReadTokens: (running?.cacheReadTokens ?? 0) + line.cacheReadTokens,
                    totalTokens: (running?.totalTokens ?? 0) + line.totalTokens,
                    cost: (running?.cost ?? 0) + line.cost
                )
            }
        }
        return totals.values.sorted {
            let left = value(of: $0), right = value(of: $1)
            return left == right ? $0.model < $1.model : left > right
        }
    }

    /// One model's part of the range, 0…1 — 0 when the range holds nothing.
    public func share(of line: ModelUsageLine) -> Double {
        let whole = total
        guard whole > 0 else { return 0 }
        return value(of: line) / whole
    }

    /// Every date of the range in order, each with its value in the unit in
    /// force and how full it is against the busiest day — the heatmap's cell, a
    /// chart's bar. A day with nothing is level 0, never a missing cell.
    public var byDay: [DayValue] {
        let busiest = stats.map { value(of: $0) }.max() ?? 0
        return stats.map { day in
            let amount = value(of: day)
            return DayValue(date: day.date, value: amount, share: busiest > 0 ? amount / busiest : 0)
        }
    }

    /// What caching saved over the range.
    public var cacheSavings: Decimal {
        stats.reduce(0) { $0 + $1.cachedSavings }
    }

    /// "$1,240.15" — what caching saved over the range.
    public var formattedCacheSavings: String {
        MoneyFormat.string(cacheSavings)
    }
}