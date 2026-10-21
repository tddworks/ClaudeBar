import Domain
import Foundation

/// The page's choice of range for the recap: this week, or the week before.
/// A week starts on the person's calendar's own first weekday.
enum RecapRange: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case lastWeek = "Last week"

    var id: String { rawValue }

    /// The range it names, in the person's calendar: the week that holds
    /// `now`, or the one before it.
    func range(containing now: Date, calendar: Calendar) -> DateRange {
        let week = Self.week(containing: now, calendar: calendar)
        return self == .thisWeek ? week : week.before(calendar: calendar)
    }

    /// What the range before this one is called — the comparison the card
    /// draws under its change. *This week* is compared with last week, and
    /// *last week* with the week before it.
    var comparedWith: String {
        switch self {
        case .thisWeek: "vs last week"
        case .lastWeek: "vs the week before"
        }
    }

    /// What the card says when this range holds nothing — never zeros.
    var emptyNote: String { "Nothing \(rawValue.lowercased())." }

    private static func week(containing now: Date, calendar: Calendar) -> DateRange {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return DateRange(first: start, last: end, calendar: calendar)
    }
}