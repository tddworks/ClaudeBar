import Domain
import Foundation

/// The recap's range choice, in words: the chip's name, what each week is
/// compared with, and what the card says of an empty one. The weeks are the
/// domain's (`RecapRange.range(containing:calendar:)`).
extension RecapRange: Identifiable {
    public var id: Self { self }

    /// The chip's name.
    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        }
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
