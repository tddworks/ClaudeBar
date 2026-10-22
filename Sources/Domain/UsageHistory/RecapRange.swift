import Foundation

/// The recap's ranges: the calendar's week or month that holds today, or the
/// one before each — each read against the range before it. The words are the
/// App's; the calendar's week and month are `DateRange`'s.
public enum RecapRange: CaseIterable, Hashable, Sendable {
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth

    /// The range it names: the calendar's week or month that holds `now`, or
    /// the one before it.
    public func range(containing now: Date, calendar: Calendar) -> DateRange {
        switch self {
        case .thisWeek: DateRange.week(containing: now, calendar: calendar)
        case .lastWeek: DateRange.week(containing: now, calendar: calendar).before(calendar: calendar)
        case .thisMonth: DateRange.month(containing: now, calendar: calendar)
        case .lastMonth: DateRange.month(containing: now, calendar: calendar).previousMonth(calendar: calendar)
        }
    }

    /// The range it is read against: the same kind, one run earlier — a week
    /// steps a week, a month steps a month.
    public func rangeBefore(containing now: Date, calendar: Calendar) -> DateRange {
        switch self {
        case .thisWeek, .lastWeek:
            range(containing: now, calendar: calendar).before(calendar: calendar)
        case .thisMonth, .lastMonth:
            range(containing: now, calendar: calendar).previousMonth(calendar: calendar)
        }
    }
}
