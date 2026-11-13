import Foundation

/// Work a Claude Code session left running when its turn ended: a shell,
/// an agent, or another task Claude wakes up from when it finishes
/// (docs/features/activity/session-hooks/design.md, *Work left running in the
/// background*). Claude Code lists them in `Stop`'s `background_tasks`.
public struct BackgroundTask: Sendable, Equatable, Codable {
    /// What kind of work runs, in the words a row uses for it.
    public enum Kind: String, Sendable, Equatable, Codable {
        case shell
        case agent
        /// A monitor, a workflow, a teammate, an MCP task, or a kind Claude
        /// Code adds later.
        case other
    }

    /// Claude Code's ID for the task.
    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}
