import Quotas
import DataSources
import Providers
import Foundation

/// Represents an active or recent Claude Code session.
/// Tracks session lifecycle, subagent activity, and task completion.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let cwd: String
    public let startedAt: Date
    public private(set) var phase: Phase
    public private(set) var activeSubagentCount: Int
    public private(set) var completedTaskCount: Int
    public private(set) var endedAt: Date?

    /// When the current turn stopped, if it has. Cleared when work resumes.
    /// Distinct from `endedAt`: a stopped session is still alive and will
    /// revive on the next `UserPromptSubmit`.
    public private(set) var stoppedAt: Date?

    /// What Claude Code is blocked on, when the session is `.awaitingInput`
    /// (e.g. "Claude needs your permission to use Bash"). Cleared when work resumes.
    public private(set) var pendingPrompt: String?

    /// The Claude Code process running this session, once a hook event has
    /// said. nil for a session whose hooks never sent one.
    public private(set) var processId: Int?

    /// The name the person gave the session with `/rename`, once its transcript has one.
    public private(set) var named: String?

    /// The title Claude Code wrote for the session, once its transcript has one.
    public private(set) var generated: String?

    /// - Parameter phase: `.active` for a session seen mid-turn; `.stopped` for
    ///   one that has just opened at its prompt — idle, with nothing finished
    ///   yet, so `finishedAt` stays nil and the notch has nothing to flash.
    public init(
        id: String,
        cwd: String,
        startedAt: Date = Date(),
        processId: Int? = nil,
        phase: Phase = .active
    ) {
        self.id = id
        self.cwd = cwd
        self.startedAt = startedAt
        self.processId = processId
        self.phase = phase
        self.activeSubagentCount = 0
        self.completedTaskCount = 0
    }

    /// The current phase of the session
    public enum Phase: String, Sendable, Equatable {
        case active
        case subagentsWorking
        /// Claude Code is blocked waiting on the user — typically a permission prompt.
        case awaitingInput
        case stopped
        case ended

        /// Human-readable label for this phase: the notch's words for the
        /// same states (docs/features/notch), so the two never disagree.
        public var label: String {
            switch self {
            case .active: return "Working"
            case .subagentsWorking: return "Agents working"
            case .awaitingInput: return "Needs you"
            case .stopped: return "Done"
            case .ended: return "Ended"
            }
        }
    }

    // MARK: - Mutations

    /// Records which process runs this session, when a later event says.
    public mutating func runs(inProcess processId: Int) {
        self.processId = processId
    }

    /// Takes the titles read from the session's transcript. A title not found
    /// this time keeps the one found before.
    public mutating func titled(_ titles: TranscriptTitles) {
        named = titles.named ?? named
        generated = titles.generated ?? generated
    }

    /// Records a subagent starting work. Subagent activity also revives a
    /// `.stopped` session: a new turn is clearly underway, so the indicator
    /// should reflect work rather than staying stuck on the previous turn's stop.
    public mutating func subagentStarted() {
        guard phase != .ended else { return }
        activeSubagentCount += 1
        updatePhase()
    }

    /// Records a subagent stopping work. Only changes the phase while agents
    /// were what defined it: Claude Code reports a subagent's stop a moment
    /// after the turn's own `Stop`, and that must not revive a stopped session
    /// or release one waiting on the person.
    public mutating func subagentStopped() {
        guard phase != .ended else { return }
        activeSubagentCount = max(0, activeSubagentCount - 1)
        if phase == .subagentsWorking {
            updatePhase()
        }
    }

    /// Revives a stopped/idle session when a new turn begins (UserPromptSubmit).
    /// `Stop` fires at the end of every turn, so without this a session would be
    /// stuck `.stopped` for the rest of its life. No-op once ended.
    public mutating func resume() {
        guard phase != .ended else { return }
        updatePhase()
    }

    /// Records that Claude Code is blocked waiting on the user, carrying the
    /// prompt it is blocked on. No-op once ended.
    public mutating func awaitInput(_ prompt: String? = nil, at date: Date = Date()) {
        guard phase != .ended else { return }
        phase = .awaitingInput
        pendingPrompt = prompt
        stoppedAt = nil
    }

    /// Records a task completion
    public mutating func taskCompleted() {
        guard phase != .ended else { return }
        completedTaskCount += 1
    }

    /// Marks the session as stopped (Claude Code stopped responding)
    public mutating func stop(at date: Date = Date()) {
        guard phase != .ended else { return }
        phase = .stopped
        activeSubagentCount = 0
        stoppedAt = date
        pendingPrompt = nil
    }

    /// Marks the session as ended
    public mutating func end(at date: Date = Date()) {
        phase = .ended
        activeSubagentCount = 0
        endedAt = date
    }

    /// When this session last finished doing something — the end of the session
    /// if it has ended, otherwise the end of the last turn. nil while working.
    ///
    /// The notch uses this to time the "done" flash; `endedAt` wins because a
    /// session that ended is finished for good, whereas a stop is provisional.
    public var finishedAt: Date? {
        endedAt ?? stoppedAt
    }

    /// The repository the session is running in — the last path component of
    /// `cwd`. This is how users refer to a session ("the claudebar one"), so it
    /// belongs here rather than being re-derived by each view.
    public var repoName: String {
        ((cwd as NSString).standardizingPath as NSString).lastPathComponent
    }

    /// What tells this session apart from others in the same repo: its name if
    /// the person gave it one, else Claude Code's title for it. nil until either is known.
    public var title: String? {
        named ?? generated
    }

    /// The repo, then the title when there is one: *claudebar · Session names*.
    public var repoAndTitle: String {
        title.map { "\(repoName) · \($0)" } ?? repoName
    }

    /// Whether this session is still active (not ended)
    public var isActive: Bool {
        phase != .ended
    }

    /// Duration of the session so far
    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Human-readable duration string
    public var durationDescription: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Private

    private mutating func updatePhase() {
        pendingPrompt = nil
        stoppedAt = nil
        if activeSubagentCount > 0 {
            phase = .subagentsWorking
        } else {
            phase = .active
        }
    }
}
