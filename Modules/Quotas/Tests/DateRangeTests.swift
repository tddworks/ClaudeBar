import Foundation
import Testing
@testable import Quotas

/// A run of the person's calendar days: every date present, and the run
/// before it, which a comparison reads (CANONICAL §5, `DateRange`).
@Suite
struct DateRangeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// The start of a fixed calendar day.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A range names each of its days, first to last.
    @Test func `should name every date of the range, in order`() {
        let week = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 18), calendar: calendar)

        #expect(week.days(in: calendar).count == 7)
        #expect(week.days(in: calendar).first == date(2026, 10, 12))
        #expect(week.days(in: calendar).last == date(2026, 10, 18))
    }

    /// The range before is as long as this one, and ends the day before it.
    @Test func `should name the same run of days one run earlier`() {
        let week = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 18), calendar: calendar)

        let before = week.before(calendar: calendar)
        #expect(before.first == date(2026, 10, 5))
        #expect(before.last == date(2026, 10, 11))
        #expect(before.days(in: calendar).count == 7)
    }

    /// A one-day range's before is the single day before it.
    @Test func `should name a single day's run before it as the day before`() {
        let day = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 12), calendar: calendar)

        let before = day.before(calendar: calendar)
        #expect(before.first == date(2026, 10, 11))
        #expect(before.last == date(2026, 10, 11))
    }

    /// A week is the calendar's own: Monday to Sunday where the week starts on
    /// a Monday.
    @Test func `should name the calendar week that holds a day`() {
        let week = DateRange.week(containing: date(2026, 10, 22), calendar: calendar)

        #expect(week.first == date(2026, 10, 19))
        #expect(week.last == date(2026, 10, 25))
        #expect(week.days(in: calendar).count == 7)
    }

    /// Where the week starts on a Sunday, so does the recap's week.
    @Test func `should start the week on the calendar's first weekday`() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1

        let week = DateRange.week(containing: date(2026, 10, 22), calendar: sundayFirst)

        #expect(week.first == date(2026, 10, 18))
        #expect(week.last == date(2026, 10, 24))
    }

    /// The week before a week is the calendar's previous week.
    @Test func `should name last week as the week before this one`() {
        let lastWeek = DateRange.week(containing: date(2026, 10, 22), calendar: calendar).before(calendar: calendar)

        #expect(lastWeek == DateRange.week(containing: date(2026, 10, 15), calendar: calendar))
    }
}
