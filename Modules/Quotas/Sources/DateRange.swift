import Foundation

/// A run of the person's calendar days, first to last — what a page asks
/// usage history for: the last two for *TODAY'S USAGE*, thirty for a chart.
/// Every day is counted in the calendar the caller gives, never `.current`:
/// `Quotas` has no platform, and on Windows Foundation's zone is GMT (#565).
/// Callers pass `DataSources.calendar()` or a log's own `calendar`.
public struct DateRange: Sendable, Equatable {
    /// The start of the first day.
    public let first: Date
    /// The start of the last day.
    public let last: Date

    /// The run from `first` to `last`, both trimmed to the day's start in
    /// `calendar`.
    public init(first: Date, last: Date, calendar: Calendar) {
        self.first = calendar.startOfDay(for: first)
        self.last = calendar.startOfDay(for: last)
    }

    /// The `count` days ending with the one that holds `day`.
    public static func last(_ count: Int, endingOn day: Date = Date(), calendar: Calendar) -> DateRange {
        let last = calendar.startOfDay(for: day)
        let first = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: last) ?? last
        return DateRange(first: first, last: last, calendar: calendar)
    }

    /// The calendar's week that holds `day`: from the calendar's own first
    /// weekday, seven days. Where the week starts is the person's calendar,
    /// never a fixed Monday.
    public static func week(containing day: Date, calendar: Calendar) -> DateRange {
        let first = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        let last = calendar.date(byAdding: .day, value: 6, to: first) ?? first
        return DateRange(first: first, last: last, calendar: calendar)
    }

    /// The same run of days, one run earlier — the range before this one, for
    /// a comparison. Its length is this range's own.
    public func before(calendar: Calendar) -> DateRange {
        let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        guard let previousFirst = calendar.date(byAdding: .day, value: -count, to: first),
              let previousLast = calendar.date(byAdding: .day, value: -count, to: last) else { return self }
        return DateRange(first: previousFirst, last: previousLast, calendar: calendar)
    }

    /// The start of every day in the range, in order.
    public func days(in calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Whether `date` falls on one of the range's days.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= first && day <= last
    }
}
