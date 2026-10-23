import Foundation

/// WHAT A PART OF A DAY SPENT — its tokens by kind and what they cost. The
/// one thing a model's line and a project's line both hold, so adding two
/// up and reading one in a unit are written once (CANONICAL §5, `Spend`).
///
/// It encodes flat — its counts beside the line's own key — so a kept line
/// reads as it was written before it held a `Spend`.
public struct Spend: Sendable, Equatable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    /// The day's token meaning — input and output, or the log's own total
    /// when it keeps only that.
    public let totalTokens: Int
    public let cost: Decimal

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0, totalTokens: Int = 0, cost: Decimal = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.cost = cost
    }

    /// Nothing spent — what a sum starts from.
    public static let none = Spend()

    /// Two spends as one: every count and the cost added, so a sum over
    /// days never drops a field a day holds.
    public static func + (lhs: Spend, rhs: Spend) -> Spend {
        Spend(inputTokens: lhs.inputTokens + rhs.inputTokens,
              outputTokens: lhs.outputTokens + rhs.outputTokens,
              cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
              cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
              totalTokens: lhs.totalTokens + rhs.totalTokens,
              cost: lhs.cost + rhs.cost)
    }

    /// What remains of a whole once a part is taken: every count and the
    /// cost less the part's.
    public static func - (whole: Spend, part: Spend) -> Spend {
        Spend(inputTokens: whole.inputTokens - part.inputTokens,
              outputTokens: whole.outputTokens - part.outputTokens,
              cacheCreationTokens: whole.cacheCreationTokens - part.cacheCreationTokens,
              cacheReadTokens: whole.cacheReadTokens - part.cacheReadTokens,
              totalTokens: whole.totalTokens - part.totalTokens,
              cost: whole.cost - part.cost)
    }

    /// The spend in `unit`: its cost, its tokens, or its cache tokens.
    public func value(in unit: Days.Unit) -> Double {
        switch unit {
        case .cost: NSDecimalNumber(decimal: cost).doubleValue
        case .tokens: Double(totalTokens)
        case .cache: Double(cacheCreationTokens + cacheReadTokens)
        }
    }
}
