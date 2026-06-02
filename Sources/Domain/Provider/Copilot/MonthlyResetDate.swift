import Foundation

/// Computes the next monthly reset instant for GitHub Copilot AI Credits.
/// GitHub's billing cycle rolls over at 00:00 UTC on the 1st of each month.
public enum MonthlyResetDate {
    /// Returns the start of the next UTC month relative to `referenceDate`.
    /// If `referenceDate` is exactly 00:00:00 UTC on the 1st, returns the 1st of the *next* month.
    public static func nextMonthlyResetDate(referenceDate: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else {
            return referenceDate
        }
        calendar.timeZone = utc
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard comps.year != nil, comps.month != nil,
              let startOfCurrent = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfCurrent)
        else {
            // Unreachable: year and month are always extractable from a Date
            return referenceDate
        }
        return nextMonth
    }
}
