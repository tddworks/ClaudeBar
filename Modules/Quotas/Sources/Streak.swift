import Foundation

/// A run of days, each under a ceiling the person set — the streak they are
/// on. Counted back from the range's last day and stopped at the first day
/// that breaches; an empty day is not a breach, so a quiet weekend does not
/// end a streak (CANONICAL §5, `Streak`).
public struct Streak: Sendable, Equatable {
    /// What "under" is measured against, in the unit the range is read in.
    public enum Threshold: Sendable, Equatable {
        /// At most this much in the unit in force — a daily budget.
        case atMost(Double)
        /// At most this share, 0…1, of the range's busiest day.
        case share(Double)
    }

    /// How many of the range's most recent days each held.
    public let length: Int
    /// How many days the range holds.
    public let daysInRange: Int
    /// The ceiling the run was counted against.
    public let threshold: Threshold

    /// Whether the run is the whole range — every day of it held.
    public var isWholeRange: Bool { daysInRange > 0 && length == daysInRange }

    public init(of days: Days, under threshold: Threshold) {
        self.threshold = threshold
        self.daysInRange = days.stats.count
        let ceiling: Double
        switch threshold {
        case .atMost(let atMost):
            ceiling = atMost
        case .share(let share):
            ceiling = share * (days.stats.map { days.value(of: $0) }.max() ?? 0)
        }
        var run = 0
        for day in days.stats.reversed() {
            guard days.value(of: day) <= ceiling else { break }
            run += 1
        }
        self.length = run
    }
}