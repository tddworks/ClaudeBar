import Domain
import Foundation

/// The recap's range choice, in words: the chip's name, what each range is
/// compared with, and what the card says of an empty one. The weeks and months
/// are the domain's (`RecapPeriod`, `RecapRange.range(containing:calendar:)`).
extension RecapRange: Identifiable {
    public var id: Self { self }

    /// The chip's name.
    var title: String {
        switch self {
        case .this(let period): "This \(period.word)"
        case .last(let period): "Last \(period.word)"
        }
    }

    /// What its change is against — the period before the one it names.
    var comparedWith: String {
        switch self {
        case .this(let period): "vs last \(period.word)"
        case .last(let period): "vs the \(period.word) before"
        }
    }

    /// What the card says when the range held nothing — never zeros.
    var emptyNote: String { "Nothing \(title.lowercased())." }
}

extension RecapPeriod {
    /// The period's word, in the pieces that say *the week* or *the month*.
    var word: String {
        switch self {
        case .week: "week"
        case .month: "month"
        }
    }
}
