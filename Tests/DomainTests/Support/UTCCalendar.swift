import Foundation

extension Calendar {
    /// UTC, so a test's calendar days are the same on every Mac.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
