import Foundation

/// A run of local calendar days, first to last — what a page asks usage
/// history for: the last two for *TODAY'S USAGE*, thirty for a chart.
public struct DateRange: Sendable, Equatable {
    /// The start of the first day.
    public let first: Date
    /// The start of the last day.
    public let last: Date

    public init(first: Date, last: Date, calendar: Calendar = .current) {
        self.first = calendar.startOfDay(for: first)
        self.last = calendar.startOfDay(for: last)
    }

    /// The `count` days ending with the one that holds `day`.
    public static func last(_ count: Int, endingOn day: Date = Date(), calendar: Calendar = .current) -> DateRange {
        let last = calendar.startOfDay(for: day)
        let first = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: last) ?? last
        return DateRange(first: first, last: last, calendar: calendar)
    }

    /// The start of every day in the range, in order.
    public func days(in calendar: Calendar = .current) -> [Date] {
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
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= first && day <= last
    }
}
