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
        // `Notification` carries `message`, a question its first question's text.
        let message = (json["error"] ?? json["message"]) as? String ?? question(in: json)

        return SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            message: message,
            processId: processId.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            transcriptPath: json["transcript_path"] as? String,
            terminal: SessionTerminal(environment: environment),
            backgroundTasks: (json["background_tasks"] as? [[String: Any]]).map(backgroundTasks)
        )
    }

    /// The first question's text when the event is about `AskUserQuestion`.
    private static func question(in json: [String: Any]) -> String? {
        guard json["tool_name"] as? String == "AskUserQuestion",
              let input = json["tool_input"] as? [String: Any],
              let questions = input["questions"] as? [[String: Any]] else { return nil }
        return questions.first?["question"] as? String
    }

    /// `Stop`'s `background_tasks`: each entry's `id` and `type`. An entry
    /// without an ID isn't one Claude Code tracks, and is skipped.
    private static func backgroundTasks(_ entries: [[String: Any]]) -> [BackgroundTask] {
        entries.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let kind: BackgroundTask.Kind = switch entry["type"] as? String {
            case "shell": .shell
            case "subagent": .agent
            default: .other
            }
            return BackgroundTask(id: id, kind: kind)
        }
    }
}
