import Foundation

/// A day's value in a unit, and how full it is against its range's busiest
/// day, 0…1 — a heatmap's cell, a chart's bar (CANONICAL §5, `DayActivity`).
public struct DayValue: Sendable, Equatable {
    /// The day, at its start.
    public let date: Date
    /// The day's value in the unit asked.
    public let value: Double
    /// How full the day is against its range's busiest, 0…1 — 0 when the
    /// range holds nothing.
    public let share: Double

    public init(date: Date, value: Double, share: Double) {
        self.date = date
        self.value = value
        self.share = share
    }
}
