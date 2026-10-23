import Foundation
import Testing
@testable import Domain

/// *Is this week's recap due?* — the calendar's week holding now, against the
/// week the last send was for, and nothing else. Due the moment the week
/// turns, in the person's calendar, and never twice in one week
/// (docs/features/alerting/recap-alerts/design.md).
@Suite
struct RecapDueTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday, as this test's person's week starts
        return calendar
    }()

    /// October 2026: Monday the 19th opens the week that holds Thursday the 22nd.
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func week(_ first: Int) -> DateRange {
        DateRange(first: date(first), last: date(first + 6), calendar: calendar)
    }

    @Test func `should be due when no recap was ever sent, naming the week that closed`() {
        let due = RecapDue.week(containing: date(22), lastSentAt: nil, calendar: calendar)

        #expect(due?.week == week(12))
    }

    @Test func `should stay quiet while the last send falls in the week under way`() {
        #expect(RecapDue.week(containing: date(22), lastSentAt: date(19), calendar: calendar) == nil)
        #expect(RecapDue.week(containing: date(22), lastSentAt: date(19, hour: 0), calendar: calendar) == nil)
    }

    @Test func `should be due from the new week's first moment`() {
        // Sent Sunday night in the week before; the week turned at midnight.
        let due = RecapDue.week(containing: date(19, hour: 0), lastSentAt: date(18, hour: 23), calendar: calendar)

        #expect(due?.week == week(12))
    }

    @Test func `should be due again once the week turns`() {
        let due = RecapDue.week(containing: date(26), lastSentAt: date(19), calendar: calendar)

        #expect(due?.week == week(19))
    }

    @Test func `should owe one recap after an absence, the latest closed week and not the weeks missed`() {
        let due = RecapDue.week(containing: date(22), lastSentAt: date(1), calendar: calendar)

        #expect(due?.week == week(12))
    }
}
