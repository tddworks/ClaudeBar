import Foundation

/// How many running sessions there are of each kind the Claude Code card
/// counts: *1 needs you · 2 working · 5 done*. Working counts sessions with
/// agents too; the card's rows tell the two apart.
public struct SessionTally: Sendable, Equatable {
    public let needsYou: Int
    public let working: Int
    public let done: Int

    public init(needsYou: Int, working: Int, done: Int) {
        self.needsYou = needsYou
        self.working = working
        self.done = done
    }
}

/// The Done sessions in one repo, folded into one row: *claudebar ×3*.
public struct DoneRepo: Sendable, Equatable, Identifiable {
    public let repoName: String
    public let count: Int
    /// The latest finish among them; a session idle since it opened counts from its start.
    public let lastFinishedAt: Date
    /// The session's title when the row stands for one session; a folded row has none.
    public let title: String?

    public var id: String { repoName }

    public init(repoName: String, count: Int, lastFinishedAt: Date, title: String? = nil) {
        self.repoName = repoName
        self.count = count
        self.lastFinishedAt = lastFinishedAt
        self.title = title
    }
}
