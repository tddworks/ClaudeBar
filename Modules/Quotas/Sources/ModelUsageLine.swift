import Foundation

/// One model's share of a day: the model and what it spent — the line a
/// chart stacks (daily-usage design §1: a `Cost` with a line per model). A
/// day has lines only when its log names models; records without a declared
/// model are the unnamed line, so the lines add up to the day.
///
/// - Note: Interim — today's shape, the line of the final `Day`
///   (docs/architecture/CANONICAL_MODEL.md §7).
public struct ModelUsageLine: UsageLine, Codable {
    /// The model as the log names it; `""` for the unnamed line.
    public let model: String
    public let spend: Spend

    public var name: String { model }

    public init(model: String, spend: Spend) {
        self.model = model
        self.spend = spend
    }

    public init(name: String, spend: Spend) {
        self.init(model: name, spend: spend)
    }

    /// A line from its counts — the shape a tally is written in.
    public init(model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0, totalTokens: Int = 0, cost: Decimal = 0) {
        self.init(model: model, spend: Spend(inputTokens: inputTokens, outputTokens: outputTokens,
                                             cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens,
                                             totalTokens: totalTokens, cost: cost))
    }

    /// A day's model lines, as the day keeps them.
    public static func split(of day: DailyUsageStat) -> [ModelUsageLine] { day.lines }

    private enum CodingKeys: String, CodingKey { case model }

    /// Flat, as kept days were written: the model beside its spend's counts.
    public init(from decoder: Decoder) throws {
        model = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .model)
        spend = try Spend(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try spend.encode(to: encoder)
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
