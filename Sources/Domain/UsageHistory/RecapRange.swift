import Foundation

/// The two weeks *WEEKLY RECAP* offers: the calendar's week that holds today,
/// or the one before it — each read against the week before it. The words
/// are the App's; the calendar's week is `DateRange.week`.
public enum RecapRange: CaseIterable, Hashable, Sendable {
    case thisWeek
    case lastWeek

    /// The week it names: the calendar's week that holds `now`, or the one
    /// before it.
    public func range(containing now: Date, calendar: Calendar) -> DateRange {
        let week = DateRange.week(containing: now, calendar: calendar)
        return self == .thisWeek ? week : week.before(calendar: calendar)
    }
}
