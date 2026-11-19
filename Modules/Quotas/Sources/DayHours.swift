import Foundation

/// WHAT A DAY KNOWS OF ITS HOURS — one of three things, each named: its
/// hours were never read, they were read and the logs no longer say, or
/// they are known. A day that used nothing knows its hours: none
/// (`DailyUsageStat` makes it so), so no state needs a second fact to mean
/// what it says (recap design §3).
public enum DayHours: Sendable, Equatable, Codable {
    /// The day was summed before hours were kept, and the logs haven't been
    /// asked since — the one state worth a read (`needsHoursRead`).
    case notRead
    /// The logs were asked and no longer hold the day: its totals stay, and
    /// when in the day they were spent is not known and won't be.
    case notKept
    /// A line per hour that held a record, in the day's order.
    case known([HourUsageLine])

    /// The hour lines, when they are known.
    public var lines: [HourUsageLine]? {
        if case .known(let lines) = self { lines } else { nil }
    }

    /// Two days of one date as one: the sum knows its hours only when both
    /// days know theirs — half a day's hours would read as the whole day's.
    /// A day still to read keeps the sum still to read.
    public static func + (lhs: DayHours, rhs: DayHours) -> DayHours {
        switch (lhs, rhs) {
        case (.known(let left), .known(let right)): .known(HourUsageLine.summed(left + right))
        case (.notRead, _), (_, .notRead): .notRead
        default: .notKept
        }
    }

    /// The word a kept day writes for hours its logs no longer hold.
    private static let notKeptMark = "notKept"

    /// The hour lines as a list, or the mark of a day whose hours were not
    /// kept. A day never read writes no hours at all (`DailyUsageStat`), so
    /// a missing key is `notRead` and a day kept before hours were still
    /// loads; written alone it is a null.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .notRead
        } else if let lines = try? container.decode([HourUsageLine].self) {
            self = .known(lines)
        } else if try container.decode(String.self) == Self.notKeptMark {
            self = .notKept
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "neither hour lines nor the not-kept mark")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .known(let lines): try container.encode(lines)
        case .notKept: try container.encode(Self.notKeptMark)
        case .notRead: try container.encodeNil()
        }
    }
}
