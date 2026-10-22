import Foundation

/// *What does my year look like* — every date of a range with its value in a
/// unit and how full it is against the busiest day. Built from `Days`; a day
/// with nothing is a value of 0, never a missing date (CANONICAL §5,
/// `DayActivity`).
public struct DayActivity: Sendable, Equatable {
    /// Every date of the range, oldest first, empty days included.
    public let days: [DayValue]
    /// The day used most, or nil when nothing was used.
    public let busiest: DayValue?

    /// `range`'s days read in `unit`, each a share of the busiest — every
    /// share 0 when the range holds nothing.
    public init(of range: Days, in unit: Days.Unit) {
        let values = range.stats.map { (date: $0.date, value: range.value(of: $0, in: unit)) }
        let most = values.map(\.value).max() ?? 0
        days = values.map { DayValue(date: $0.date, value: $0.value, share: most > 0 ? $0.value / most : 0) }
        busiest = most > 0 ? days.first { $0.value == most } : nil
    }
}
