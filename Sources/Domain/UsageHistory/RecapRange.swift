import Foundation

/// The recap's ranges: this period or the last one, of a week or a month —
/// each read against the period before it. The span is `RecapPeriod`'s; the
/// words are the App's.
public enum RecapRange: CaseIterable, Hashable, Sendable {
    /// The period that holds today.
    case this(RecapPeriod)
    /// The period before the one that holds today.
    case last(RecapPeriod)

    /// Every range the recap offers, a period's two together: this week, last
    /// week, this month, last month.
    public static let allCases: [RecapRange] = RecapPeriod.allCases.flatMap { [.this($0), .last($0)] }

    /// The span it adds up.
    public var period: RecapPeriod {
        switch self {
        case .this(let period), .last(let period): period
        }
    }

    /// The range it names: the period that holds `now`, or the one before it.
    public func range(containing now: Date, calendar: Calendar) -> DateRange {
        switch self {
        case .this(let period): period.range(containing: now, calendar: calendar)
        case .last(let period): period.before(period.range(containing: now, calendar: calendar), calendar: calendar)
        }
    }

    /// The range it is read against: the period before the one it names.
    public func rangeBefore(containing now: Date, calendar: Calendar) -> DateRange {
        period.before(range(containing: now, calendar: calendar), calendar: calendar)
    }
}
