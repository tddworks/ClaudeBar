import Foundation

/// The span a recap adds up: the calendar's week or its month. It owns which
/// days the one holding a day covers, and the one before it — the period
/// holding the day before this one starts. One rule for both, so a month
/// steps a month and never a day-count back.
public enum RecapPeriod: CaseIterable, Hashable, Sendable {
    case week
    case month

    /// The calendar's week or month that holds `day`.
    public func range(containing day: Date, calendar: Calendar) -> DateRange {
        switch self {
        case .week: DateRange.week(containing: day, calendar: calendar)
        case .month: DateRange.month(containing: day, calendar: calendar)
        }
    }

    /// The period before `range`: the one holding the day before it starts.
    public func before(_ range: DateRange, calendar: Calendar) -> DateRange {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: range.first) ?? range.first
        return self.range(containing: dayBefore, calendar: calendar)
    }
}
