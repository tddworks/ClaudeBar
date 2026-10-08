import Foundation

/// A RANGE OF DAYS — the one answer `UsageHistory.days(in:)` returns, and
/// every view's questions answered: which models, in order; a day's lines,
/// largest first; its total in a unit. A view renders what this says and
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
        knowsCost ? NSDecimalNumber(decimal: day.totalCost).doubleValue : Double(day.totalTokens)
    }

    /// The range's total in the unit in force.
    public var total: Double {
        stats.reduce(0) { $0 + value(of: $1) }
    }

    /// A line's part in the unit in force.
    public func value(of line: ModelUsageLine) -> Double {
        knowsCost ? NSDecimalNumber(decimal: line.cost).doubleValue : Double(line.totalTokens)
    }
}
