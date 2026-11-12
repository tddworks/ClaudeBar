import Foundation
import Domain

/// Parses Claude Code hook event JSON payloads into SessionEvent domain objects.
public enum SessionEventParser {
    /// Parses raw JSON data from a hook HTTP request into a SessionEvent.
    /// Claude Code sends JSON with fields: session_id, hook_event_name, cwd, etc.
    /// `processId` is the hook's `X-ClaudeBar-Pid` header: the Claude Code
    /// process ID, or empty when the hook had none to send. `environment` is
    /// what the hook found in Claude Code's environment, by variable name, to
    /// tell where the session runs.
    public static func parse(_ data: Data, processId: String? = nil, environment: [String: String] = [:]) -> SessionEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let sessionId = json["session_id"] as? String,
              let eventNameRaw = json["hook_event_name"] as? String,
              let eventName = SessionEvent.EventName(rawValue: eventNameRaw) else {
            return nil
        }

        let cwd = json["cwd"] as? String ?? ""
        // What the event is about, when it says: `StopFailure` carries `error`,
        // `Notification` carries `message`.
        let message = (json["error"] ?? json["message"]) as? String

        return SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            message: message,
            processId: processId.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            transcriptPath: json["transcript_path"] as? String,
            terminal: SessionTerminal(environment: environment)
        )
    }
}
