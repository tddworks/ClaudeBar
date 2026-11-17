import Foundation

/// A RANGE OF DAYS — the one answer `UsageHistory.days(in:)` returns, and
/// every view's questions answered: which models, in order; a day's lines,
/// largest first; its total in a unit; which units it offers. A view renders
/// what this says and never counts for itself (CANONICAL §5, `Days`).
public struct Days: Sendable, Equatable {
    /// What a range is counted in — the one choice a view makes about it.
    /// `cost` is offered only when a day holds one (daily-usage design §1).
    public enum Unit: Sendable, Equatable, CaseIterable {
        case cost
        case tokens
        case cache
    }

    /// Every date of the range, empty days included.
    public let stats: [DailyUsageStat]
    /// Whether the log prices its records at all — a unit's first question.
    public let knowsCost: Bool

    public init(_ stats: [DailyUsageStat], knowsCost: Bool) {
        self.stats = stats
        self.knowsCost = knowsCost
    }

    /// The models the days name, in name order — a model keeps its colour
    /// from day to day. The unnamed line is not a model.
    public var models: [String] {
        Set(stats.flatMap { $0.lines.map(\.model) }).filter { !$0.isEmpty }.sorted()
    }

    /// Whether a model split is offered — whether any day names a model.
    public var hasModels: Bool {
        stats.contains { $0.lines.contains { !$0.model.isEmpty } }
    }

    /// Whether cost says anything: the log prices its records AND a day holds
    /// a cost. A log that writes a cost of zero everywhere — free models,
    /// OpenCode's `cost: 0` — has nothing to say in dollars.
    public var hasCost: Bool {
        knowsCost && stats.contains { $0.totalCost > 0 }
    }

    /// The units this range offers, in order — no cost when no day holds one.
    public var units: [Unit] {
        hasCost ? Unit.allCases : Unit.allCases.filter { $0 != .cost }
    }

    /// The unit a view opens on: cost when the range offers it, tokens when not.
    public var defaultUnit: Unit { hasCost ? .cost : .tokens }

    /// A day's lines, largest part first in `unit` — the unnamed line among
    /// them, so they add up to the day.
    public func lines(of day: DailyUsageStat, in unit: Unit) -> [ModelUsageLine] {
        day.lines.sorted { $0.spend.value(in: unit) > $1.spend.value(in: unit) }
    }

    /// Each model's part of the whole range, largest first in `unit` — the
    /// unnamed line among them, so they add up to the range's total.
    public func lines(in unit: Unit) -> [ModelUsageLine] {
        var spends: [String: Spend] = [:]
        for line in stats.flatMap(\.lines) {
            spends[line.model, default: .none] = spends[line.model, default: .none] + line.spend
        }
        return spends.map { ModelUsageLine(model: $0.key, spend: $0.value) }.sorted {
            let (lhs, rhs) = ($0.spend.value(in: unit), $1.spend.value(in: unit))
            return lhs != rhs ? lhs > rhs : $0.model < $1.model
        }
    }

    /// The range's models, in the range's order, each with its part of `day`
    /// — nothing for a model the day didn't use — so a list that switches
    /// from the range to a day keeps its rows where they were.
    public func lines(in unit: Unit, on day: DailyUsageStat) -> [ModelUsageLine] {
        lines(in: unit).map { range in
            ModelUsageLine(model: range.model,
                           spend: day.lines.first { $0.model == range.model }?.spend ?? .none)
        }
    }

    /// A day's total in `unit`.
    public func value(of day: DailyUsageStat, in unit: Unit) -> Double {
        day.spend.value(in: unit)
    }

    /// The range's total in `unit`.
    public func total(in unit: Unit) -> Double {
        stats.reduce(0) { $0 + value(of: $1, in: unit) }
    }


    /// What caching saved over the range.
    public var cacheSavings: Decimal {
        stats.reduce(0) { $0 + $1.cachedSavings }
    }

    /// Whether no day of the range holds anything.
    public var isEmpty: Bool { stats.allSatisfy(\.isEmpty) }

    /// The time worked over the range.
    public var workingTime: TimeInterval { stats.reduce(0) { $0 + $1.workingTime } }

    /// The sessions over the range.
    public var sessions: Int { stats.reduce(0) { $0 + $1.sessionCount } }

    /// Several ranges read as one: each date once, oldest first, its days
    /// added up (`DailyUsageStat +`). Cost speaks for the whole only when every
    /// range that read something prices its records.
    public static func merged(_ ranges: [Days]) -> Days {
        var byDate: [Date: DailyUsageStat] = [:]
        for day in ranges.flatMap(\.stats) {
            byDate[day.date] = byDate[day.date].map { $0 + day } ?? day
        }
        // A range that read nothing has no say in what the others cost.
        let used = ranges.filter { !$0.isEmpty }
        return Days(byDate.values.sorted { $0.date < $1.date }, knowsCost: used.allSatisfy(\.knowsCost))
    }
}
