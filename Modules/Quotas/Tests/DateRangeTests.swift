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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func `should name every date of the range, in order`() {
        let week = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 18), calendar: calendar)

        #expect(week.days(in: calendar).count == 7)
        #expect(week.days(in: calendar).first == date(2026, 10, 12))
        #expect(week.days(in: calendar).last == date(2026, 10, 18))
    }

    @Test func `should name the same run of days one run earlier`() {
        let week = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 18), calendar: calendar)

        let before = week.before(calendar: calendar)
        #expect(before.first == date(2026, 10, 5))
        #expect(before.last == date(2026, 10, 11))
        #expect(before.days(in: calendar).count == 7)
    }

    @Test func `should name a single day's run before it as the day before`() {
        let day = DateRange(first: date(2026, 10, 12), last: date(2026, 10, 12), calendar: calendar)

        let before = day.before(calendar: calendar)
        #expect(before.first == date(2026, 10, 11))
        #expect(before.last == date(2026, 10, 11))
    }
}