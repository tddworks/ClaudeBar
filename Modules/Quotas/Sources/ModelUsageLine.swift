import Foundation

/// One model's share of a day: the tokens it spent and what they cost — the
/// line a chart stacks (daily-usage design §1: a `Cost` with a line per
/// model). A day has lines only when its log names models; a record without
/// a declared model stays in the day's totals alone.
///
/// - Note: Interim — today's shape, the line of the final `Day`
///   (docs/architecture/CANONICAL_MODEL.md §7).
public struct ModelUsageLine: Sendable, Equatable, Codable {
    /// The model as the log names it.
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    /// The day's token meaning — input and output, or the log's own total
    /// when it keeps only that.
    public let totalTokens: Int
    public let cost: Decimal

    public init(model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0, totalTokens: Int = 0, cost: Decimal = 0) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.cost = cost
    }

    /// "$1.50" — the line's cost.
    public var formattedCost: String {
        MoneyFormat.string(cost)
    }

    /// The model's name for a tight row, by a mechanical rule, no vendor
    /// named: a trailing `:<size>` goes (`qwen3-coder:30b` reads
    /// *qwen3-coder*), a trailing `-YYYYMMDD` date goes, and a leading
    /// segment goes when at least two remain (`claude-opus-4-6` reads
    /// *opus-4-6*). A name with nothing to strip reads as it is; the unnamed
    /// line reads as a dash.
    public var displayName: String { Self.displayName(model) }

    public static func displayName(_ model: String) -> String {
        guard !model.isEmpty else { return "—" }
        var name = Substring(model)
        if let tag = name.firstIndex(of: ":") { name = name[..<tag] }
        if let dash = name.index(name.endIndex, offsetBy: -9, limitedBy: name.startIndex),
           name[dash] == "-", name[name.index(after: dash)...].allSatisfy(\.isNumber) {
            name = name[..<dash]
        }
        let segments = name.split(separator: "-")
        if segments.count > 2 { name = name.dropFirst(segments[0].count + 1) }
        return String(name)
    }
}
