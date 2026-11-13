import Domain

extension ClaudeSession {
    /// What the session left running in the background, in a row's words:
    /// *1 shell*, *2 agents*, or *3 tasks* when they are of several kinds; nil
    /// when nothing runs (docs/features/activity/session-hooks/design.md,
    /// *Work left running in the background*).
    var backgroundWorkText: String? {
        guard let first = backgroundTasks.first else { return nil }
        let count = backgroundTasks.count
        let oneKind = backgroundTasks.allSatisfy { $0.kind == first.kind }
        let noun = switch oneKind ? first.kind : .other {
        case .shell: "shell"
        case .agent: "agent"
        case .other: "task"
        }
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
