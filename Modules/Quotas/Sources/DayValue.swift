import Foundation

/// A day's value in the unit its range is read in, and how full it is against
/// that range's busiest day — the heatmap's cell and a chart's bar. A day with
/// nothing is level 0: a cell, never a gap (CANONICAL §5, `Days`).
public struct DayValue: Sendable, Equatable {
    /// The day, at its start.
    public let date: Date
    /// The day's value in the unit in force.
    public let value: Double
    /// How full the day is against its range's busiest, 0…1 — 0 when the range
    /// holds nothing.
    public let share: Double

    /// A day's value in its range's unit, and how full it is against that
    /// range's busiest, 0…1 — 0 when the range holds nothing.
    public init(date: Date, value: Double, share: Double) {
        self.date = date
        self.value = value
        self.share = share
    }

    /// The heatmap's shade: 0 for a day with nothing, else 1…4 by `share` —
    /// how full the day is, never a colour.
    public var level: Int {
        guard value > 0, share > 0 else { return 0 }
        return max(1, min(4, Int((share * 4).rounded(.up))))
    }
}