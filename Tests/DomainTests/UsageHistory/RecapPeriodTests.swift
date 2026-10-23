import Testing
import Foundation
@testable import Domain

/// The span a recap adds up — the calendar's week or month — and the one
/// before it: the period holding the day before this one starts. A month
/// steps a month, never a day-count back.
@Suite
struct RecapPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func `should span the calendar week that holds a day`() {
        #expect(RecapPeriod.week.range(containing: date(2026, 10, 22), calendar: calendar)
            == DateRange.week(containing: date(2026, 10, 22), calendar: calendar))
    }

    @Test func `should span the calendar month that holds a day`() {
        #expect(RecapPeriod.month.range(containing: date(2026, 10, 22), calendar: calendar)
            == DateRange.month(containing: date(2026, 10, 22), calendar: calendar))
    }

    @Test func `should name the week before as the seven days before it starts`() {
        let week = RecapPeriod.week.range(containing: date(2026, 10, 22), calendar: calendar)
        let before = RecapPeriod.week.before(week, calendar: calendar)

        #expect(before.first == date(2026, 10, 12))
        #expect(before.last == date(2026, 10, 18))
    }

    /// Months differ in length: stepping March's 31 days back from March 1
    /// would land in January.
    @Test func `should name the previous calendar month, not a day-count back`() {
        let march = RecapPeriod.month.range(containing: date(2026, 3, 15), calendar: calendar)
        let before = RecapPeriod.month.before(march, calendar: calendar)

        #expect(before.first == date(2026, 2, 1))
        #expect(before.last == date(2026, 2, 28))
    }

    @Test func `should name a thirty-one-day month before a thirty-day one`() {
        let may = RecapPeriod.month.range(containing: date(2026, 5, 9), calendar: calendar)
        let before = RecapPeriod.month.before(RecapPeriod.month.range(containing: date(2026, 6, 9), calendar: calendar),
                                              calendar: calendar)

        #expect(before == may)
        #expect(before.days(in: calendar).count == 31)
    }

    @Test func `should cross a year when stepping back from January`() {
        let january = RecapPeriod.month.range(containing: date(2026, 1, 9), calendar: calendar)
        let before = RecapPeriod.month.before(january, calendar: calendar)

        #expect(before.first == date(2025, 12, 1))
        #expect(before.last == date(2025, 12, 31))
    }
}
