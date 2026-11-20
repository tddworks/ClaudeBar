import Foundation

/// The factory: Activity's objects that reach this Mac, handed out as the
/// ports the App composes, so it never names an implementation.
public enum Activity {
    /// Claude Code's hook events, received on the local hook server.
    public static func makeHookReceiver() -> any HookEventReceiver {
        HookHTTPServer()
    }

    /// ClaudeBar's hooks in Claude Code's settings.
    public static func makeHookInstallation() -> any HookInstallation {
        SettingsFileHooks()
    }

    /// A session's names, read from its transcript.
    public static func makeSessionTitles() -> any SessionTitles {
        TranscriptTitleReader()
    }

    /// Brings a session's terminal forward.
    public static func makeTerminalFocus() -> any TerminalFocus {
        ScriptedTerminalFocus()
    }

    /// Whether a session's process still runs.
    public static func makeProcessLiveness() -> any ProcessLiveness {
        SystemProcessLiveness()
    }
}
