import Domain
import Foundation

/// The recap's range choice on the All page: this week, or the week before.
/// The calendar's week is `DateRange.week`; this only names the two and what
/// each is compared with.
enum RecapRange: CaseIterable, Identifiable, Hashable {
    case thisWeek
    case lastWeek

    var id: Self { self }

    /// The chip's name.
    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        }
    }

    /// The week it names: the calendar's week that holds `now`, or the one
    /// before it.
    func range(containing now: Date, calendar: Calendar) -> DateRange {
        let week = DateRange.week(containing: now, calendar: calendar)
        return self == .thisWeek ? week : week.before(calendar: calendar)
    }

    /// What its change is against — the week before the one it names.
    var comparedWith: String {
        switch self {
        case .thisWeek: "vs last week"
        case .lastWeek: "vs the week before"
        }
    }

    /// What the card says when the week held nothing — never zeros.
    var emptyNote: String { "Nothing \(title.lowercased())." }
}
