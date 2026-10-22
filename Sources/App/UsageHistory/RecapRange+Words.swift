import Domain
import Foundation

/// The recap's range choice, in words: the chip's name, what each range is
/// compared with, and what the card says of an empty one. The weeks and months
/// are the domain's (`RecapRange.range(containing:calendar:)`).
extension RecapRange: Identifiable {
    public var id: Self { self }

    /// The chip's name.
    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        }
    }

    /// What its change is against — the range before the one it names.
    var comparedWith: String {
        switch self {
        case .thisWeek: "vs last week"
        case .lastWeek: "vs the week before"
        case .thisMonth: "vs last month"
        case .lastMonth: "vs the month before"
        }
    }

    /// What the card says when the range held nothing — never zeros.
    var emptyNote: String { "Nothing \(title.lowercased())." }

    /// Whether the range names a month — the report reads a month's day by
    /// day quieter than a week's seven.
    var isMonth: Bool { self == .thisMonth || self == .lastMonth }
}
