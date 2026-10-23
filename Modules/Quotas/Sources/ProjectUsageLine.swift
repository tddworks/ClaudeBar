import Foundation

/// One project's share of a day: the project and what its records spent —
/// usage attributed to the working directory it was spent in. A day keeps
/// lines for its named projects only; what remains of the day is the
/// unnamed part of its split, worked out by the day
/// (`DailyUsageStat.projectSplit`; quota-by-project design §2–3).
public struct ProjectUsageLine: UsageLine, Codable {
    /// The project, named by the working directory's last path component —
    /// never the absolute path. The unnamed part is the empty name.
    public let project: String
    public let spend: Spend

    public var name: String { project }

    public init(project: String, spend: Spend) {
        self.project = project
        self.spend = spend
    }

    public init(name: String, spend: Spend) {
        self.init(project: name, spend: spend)
    }

    /// A line from its counts — the shape a tally is written in.
    public init(project: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0, totalTokens: Int = 0, cost: Decimal = 0) {
        self.init(project: project, spend: Spend(inputTokens: inputTokens, outputTokens: outputTokens,
                                                 cacheCreationTokens: cacheCreationTokens,
                                                 cacheReadTokens: cacheReadTokens, totalTokens: totalTokens,
                                                 cost: cost))
    }

    /// A day's project split: its named lines and what remains of it.
    public static func split(of day: DailyUsageStat) -> [ProjectUsageLine] { day.projectSplit }

    private enum CodingKeys: String, CodingKey { case project }

    /// Flat, as a model's line is: the project beside its spend's counts.
    public init(from decoder: Decoder) throws {
        project = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .project)
        spend = try Spend(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(project, forKey: .project)
        try spend.encode(to: encoder)
    }

    /// The project's name for a tight row: as the aggregation named it, or a
    /// dash for the unnamed part.
    public var displayName: String { Self.displayName(project) }

    /// The name a project shows as: itself, or a dash for the unnamed part.
    public static func displayName(_ project: String) -> String {
        project.isEmpty ? "—" : project
    }

    /// The project a working directory names: its last path component — the
    /// one place the naming happens, so a day is never kept or shown with a
    /// path. A directory with no folder in it names itself; a name a person
    /// can read is the point.
    public static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
