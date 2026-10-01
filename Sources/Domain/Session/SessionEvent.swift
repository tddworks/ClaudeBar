import Foundation

/// Represents a hook event received from Claude Code.
/// These events map directly to Claude Code's hook system events.
public struct SessionEvent: Sendable, Equatable, Codable {
    /// The session ID from Claude Code
    public let sessionId: String

    /// The type of hook event
    public let eventName: EventName

    /// The working directory where Claude Code is running
    public let cwd: String

    /// When this event was received
    public let receivedAt: Date

    /// Free-text payload carried by the event, when the hook provides one.
    /// `Notification` uses it for what Claude Code is blocked on
    /// (e.g. "Claude needs your permission to use Bash").
    public let message: String?

    public init(
        sessionId: String,
        eventName: EventName,
        cwd: String,
        receivedAt: Date = Date(),
        message: String? = nil
    ) {
        self.sessionId = sessionId
        self.eventName = eventName
        self.cwd = cwd
        self.receivedAt = receivedAt
        self.message = message
    }

    /// Whether this event originates from ClaudeBar's own background quota probe.
    ///
    /// ClaudeBar refreshes quotas by spawning `claude /usage` in
    /// `<AppSupport>/ClaudeBar/Probe`. Claude Code fires SessionStart/SessionEnd
    /// hooks for that run, which loop back into ClaudeBar's own hook server. These
    /// events must be ignored so routine background polling doesn't pollute the
    /// recent-sessions list or fire "Claude Code Finished: Probe" notifications.
    /// (issue #172)
    public var isClaudeBarProbe: Bool {
        let components = ((cwd as NSString).standardizingPath as NSString).pathComponents
        return Array(components.suffix(2)) == ["ClaudeBar", "Probe"]
    }

    /// The types of hook events from Claude Code
    public enum EventName: String, Sendable, Equatable, Codable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case taskCompleted = "TaskCompleted"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        case stop = "Stop"
        /// Fires at the start of every turn (before Claude processes the prompt).
        /// Used to revive a session out of `.stopped` so the indicator tracks
        /// real activity instead of sticking on the end-of-turn `Stop`.
        case userPromptSubmit = "UserPromptSubmit"
        /// Fires when Claude Code needs the user — most importantly a
        /// permission prompt. The session is blocked until it is answered.
        case notification = "Notification"
    }
}
