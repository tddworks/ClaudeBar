import Quotas
import DataSources
import Providers
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

    /// The Claude Code process the event came from, when the hook said.
    /// Lets ClaudeBar notice a session whose process died without a `SessionEnd`.
    public let processId: Int?

    /// The transcript the session writes to (`transcript_path`), when the hook said.
    public let transcriptPath: String?

    /// The titles found in the session's transcript when the event arrived;
    /// nil when nobody has read them.
    public let titles: TranscriptTitles?

    public init(
        sessionId: String,
        eventName: EventName,
        cwd: String,
        receivedAt: Date = Date(),
        message: String? = nil,
        processId: Int? = nil,
        transcriptPath: String? = nil,
        titles: TranscriptTitles? = nil
    ) {
        self.sessionId = sessionId
        self.eventName = eventName
        self.cwd = cwd
        self.receivedAt = receivedAt
        self.message = message
        self.processId = processId
        self.transcriptPath = transcriptPath
        self.titles = titles
    }

    /// This event, carrying the titles read from its session's transcript.
    public func titled(_ titles: TranscriptTitles) -> SessionEvent {
        SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            receivedAt: receivedAt,
            message: message,
            processId: processId,
            transcriptPath: transcriptPath,
            titles: titles
        )
    }

    /// Whether this event must be ignored as ClaudeBar's own background probe traffic.
    ///
    /// ClaudeBar refreshes quotas by spawning `claude /usage` in
    /// `<AppSupport>/ClaudeBar/Probe`. Claude Code fires SessionStart/SessionEnd
    /// hooks for that run, which loop back into ClaudeBar's own hook server. These
    /// events must be ignored so routine background polling doesn't pollute the
    /// recent-sessions list or fire "Claude Code Finished: Probe" notifications.
    ///
    /// Two signals mark them: the probe working directory (issue #172), and —
    /// since #222 — an event with no attributable working directory at all.
    /// The probe's hook payloads can arrive with `cwd` missing or reshaped by a
    /// CLI update; an event that can't say where it ran is indistinguishable
    /// from probe noise and couldn't name a project anyway, so it is dropped.
    /// (The primary defense is upstream of this filter: probe sessions are
    /// spawned with `CLAUDEBAR_PROBE=1` and the installed hook command exits
    /// before POSTing when it sees it.)
    public var isClaudeBarProbe: Bool {
        guard !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
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
        /// Fires instead of `Stop` when the turn ends in an error — an API
        /// connection lost while the Mac slept, say. The turn is over either way.
        case stopFailure = "StopFailure"
        /// Fires at the start of every turn (before Claude processes the prompt).
        /// Used to revive a session out of `.stopped` so the indicator tracks
        /// real activity instead of sticking on the end-of-turn `Stop`.
        case userPromptSubmit = "UserPromptSubmit"
        /// Fires when Claude Code needs the user — most importantly a
        /// permission prompt. The session is blocked until it is answered.
        case notification = "Notification"
    }
}
