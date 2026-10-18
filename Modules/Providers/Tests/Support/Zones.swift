import Foundation
import Mockable
@testable import DataSources

/// A person's time zone, fixed: what `Platform.timeZone` answers in a test,
/// so a date a script works out is the same on every machine and CI runner.
enum Zones {
    static func fixed(_ identifier: String) -> MockTimeZoneSource {
        let source = MockTimeZoneSource()
        given(source).current().willReturn(TimeZone(identifier: identifier)!)
        return source
    }

    /// Clocks go forward on 2026-03-08 and 2027-03-14, so a month that
    /// takes either in is an hour short.
    static var losAngeles: MockTimeZoneSource { fixed("America/Los_Angeles") }

    /// The person's calendar in Los Angeles: what a test's expected dates use.
    static var losAngelesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
}
