import Foundation

/// One project's share of a day: the tokens its records spent and what they
/// cost — usage attributed to the working directory it was spent in. A day
/// has project lines only when its log names a directory; records with none
/// form one unnamed part, so the parts add up to the day
/// (quota-by-project design §2–3).
public struct ProjectUsageLine: Sendable, Equatable, Codable {
    /// The project, named by the working directory's last path component —
    /// never the absolute path. The unnamed part is the empty name.
    public let project: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    /// The day's token meaning — input and output, or the log's own total
    /// when it keeps only that.
    public let totalTokens: Int
    public let cost: Decimal

    /// A line with every count empty, ready to be added into.
    public init(project: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0, totalTokens: Int = 0, cost: Decimal = 0) {
        self.project = project
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.cost = cost
    }

    /// Two lines of one project as one: every count and the cost added, so a
    /// sum over days never drops a field a day holds.
    public static func + (lhs: ProjectUsageLine, rhs: ProjectUsageLine) -> ProjectUsageLine {
        precondition(lhs.project == rhs.project, "only lines of one project add up")
        return ProjectUsageLine(
            project: lhs.project,
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            cost: lhs.cost + rhs.cost
        )
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
