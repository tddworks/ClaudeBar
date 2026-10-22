import Foundation
import Domain

/// A range of days laid out as a heatmap: a column a week, seven rows a week,
/// the calendar's weekday order — what a GitHub-style heatmap draws. Every
/// date of the range is one cell; the slots before the first day and after the
/// last are empty, never a day.
///
/// A value, not a view, so "every date is a cell" and "an empty day is a cell,
/// not a gap" are tested as state, with no screen in the loop.
struct UsageHeatmap {
    /// Where a month starts, for the labels above the grid.
    struct MonthMark: Equatable {
        /// The column the month's first day falls in.
        let column: Int
        /// The month's first day.
        let month: Date
    }

    /// One column a week, oldest first; seven slots each, `nil` outside the range.
    let weeks: [[DayValue?]]
    /// Where each month the range covers starts, oldest first.
    let monthMarks: [MonthMark]
    /// The calendar's weekday order (1 = Sunday), so the rows can be labelled.
    let firstWeekday: Int

    /// The shading bands, lightest first — one legend square each.
    static let levels = 0...4

    /// A day's band: 0 for a day with nothing, else 1…4 by its share of the
    /// busiest day — how full it is, never a colour.
    static func level(of day: DayValue) -> Int {
        guard day.value > 0, day.share > 0 else { return 0 }
        return max(1, min(4, Int((day.share * 4).rounded(.up))))
    }

    /// Lays `days` out a column a week, oldest first, in `calendar`'s
    /// weekday order — the slots outside the range empty, never a day.
    init(_ days: [DayValue], calendar: Calendar = .current) {
        firstWeekday = calendar.firstWeekday
        let leading = days.first.map {
            (calendar.component(.weekday, from: $0.date) - calendar.firstWeekday + 7) % 7
        } ?? 0
        var slots: [DayValue?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while slots.count % 7 != 0 { slots.append(nil) }
        weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<($0 + 7)]) }

        var marks: [MonthMark] = []
        var seen: Set<Date> = []
        for (position, day) in days.enumerated() {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day.date)),
                  seen.insert(month).inserted else { continue }
            marks.append(MonthMark(column: (leading + position) / 7, month: month))
        }
        // A range that starts late in a month leaves the next month only a
        // column or two away, and two 7 pt labels would overlap; the crowded
        // first month goes unlabelled.
        if marks.count > 1, marks[1].column - marks[0].column < 3 {
            marks.removeFirst()
        }
        monthMarks = marks
    }
}