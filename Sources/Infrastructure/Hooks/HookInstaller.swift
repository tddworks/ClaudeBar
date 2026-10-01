import Foundation
import Domain

/// Installs and uninstalls ClaudeBar hooks in ~/.claude/settings.json.
/// Hook commands use the __claudebar_hook function wrapper for identification.
public enum HookInstaller {
    /// The marker function name used to identify ClaudeBar hooks
    static let hookMarker = "__claudebar_hook"

    /// The settings file path
    public static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    /// The hook command template. Port is read from the discovery file at runtime.
    static let hookCommand = """
    __claudebar_hook() { PORT=$(cat "$HOME/.claude/claudebar-hook-port" 2>/dev/null || echo \(HookConstants.defaultPort)); cat | curl -s -X POST "http://localhost:${PORT}/hook" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1 & }; __claudebar_hook
    """

    /// The event names to register hooks for
    static let hookEvents = [
        "SessionStart",
        "SessionEnd",
        "TaskCompleted",
        "SubagentStart",
        "SubagentStop",
        "Stop",
        "UserPromptSubmit",
    ]

    /// Installs hooks into the Claude settings file.
    /// Creates the file and directory if they don't exist.
    /// Preserves existing settings and hooks from other tools.
    ///
    /// Hook format (new matcher-based format):
    /// ```json
    /// {"SessionStart": [{"matcher": ".*", "hooks": [{"type": "command", "command": "..."}]}]}
    /// ```
    public static func install() throws {
        var settings = try readOrCreateSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [String: Any]()

        for event in hookEvents {
            var matcherEntries = hooks[event] as? [[String: Any]] ?? [[String: Any]]()

            // Remove any existing ClaudeBar matcher entries for this event
            matcherEntries.removeAll { entry in
                containsClaudeBarHook(in: entry)
            }

            // Add the new hook in matcher format
            matcherEntries.append([
                "matcher": ".*",
                "hooks": [
                    [
                        "type": "command",
                        "command": hookCommand,
                    ] as [String: Any]
                ],
            ])

            hooks[event] = matcherEntries
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    /// Uninstalls ClaudeBar hooks from the Claude settings file.
    /// Preserves hooks from other tools.
    public static func uninstall() throws {
        guard var settings = try? readOrCreateSettings() else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in hookEvents {
            guard var matcherEntries = hooks[event] as? [[String: Any]] else { continue }

            matcherEntries.removeAll { entry in
                containsClaudeBarHook(in: entry)
            }

            if matcherEntries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = matcherEntries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings)
    }

    /// Detects whether ClaudeBar hooks are currently installed.
    public static func isInstalled() -> Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }

        // Check if at least one event has our hook (in matcher format)
        return hooks.values.contains { value in
            guard let matcherEntries = value as? [[String: Any]] else { return false }
            return matcherEntries.contains { entry in
                containsClaudeBarHook(in: entry)
            }
        }
    }

    /// Checks if a matcher entry contains a ClaudeBar hook command.
    private static func containsClaudeBarHook(in matcherEntry: [String: Any]) -> Bool {
        guard let innerHooks = matcherEntry["hooks"] as? [[String: Any]] else { return false }
        return innerHooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(hookMarker)
        }
    }

    // MARK: - Private

    enum InstallerError: Error {
        case corruptedSettingsFile(String)
    }

    /// Reads settings, returning empty dict for missing file but throwing on corrupt JSON.
    static func readOrCreateSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath) else {
            return [String: Any]()
        }

        guard let data = FileManager.default.contents(atPath: settingsPath) else {
            return [String: Any]()
        }

        // Empty file is treated as empty settings
        if data.isEmpty {
            return [String: Any]()
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.corruptedSettingsFile(
                "Failed to parse \(settingsPath) — file may be corrupted. Fix it manually before retrying."
            )
        }

        return json
    }

    /// For read-only checks (isInstalled) — returns nil on any error.
    static func readSettings() -> [String: Any]? {
        try? readOrCreateSettings()
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let directory = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }
}
