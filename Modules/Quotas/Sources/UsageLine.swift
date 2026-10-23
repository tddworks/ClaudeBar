import Foundation

/// A LINE OF A DAY'S SPLIT — the day split by something, a model or a
/// project: the line's name and what it spent. The empty name is the
/// unnamed part. What differs between the splits is only the key and which
/// lines a day offers, so the sum and the mix over them are written once
/// (CANONICAL §5, `UsageLine`; `UsageMix`).
public protocol UsageLine: Sendable, Equatable {
    /// The key the line is split by — `""` for the unnamed part.
    var name: String { get }
    /// What the line's records spent.
    var spend: Spend { get }

    init(name: String, spend: Spend)

    /// The lines this split takes from a day, adding up to it when it has any.
    static func split(of day: DailyUsageStat) -> [Self]
}

extension UsageLine {
    /// Two lines of one name as one: their spends added.
    public static func + (lhs: Self, rhs: Self) -> Self {
        precondition(lhs.name == rhs.name, "only lines of one name add up")
        return Self(name: lhs.name, spend: lhs.spend + rhs.spend)
    }

    /// `lines` added up per name, one line each, in name order.
    public static func summed(_ lines: [Self]) -> [Self] {
        var sums: [String: Self] = [:]
        for line in lines {
            sums[line.name] = sums[line.name].map { $0 + line } ?? line
        }
        return sums.values.sorted { $0.name < $1.name }
    }
}
