import Foundation
import Domain

/// What `ScriptedTerminalFocus` runs to bring a session forward: the
/// AppleScript for its terminal, the `tmux` commands for its pane and the app
/// to activate. Only text and arguments; running them is the focus's job.
enum TerminalScripts {
    /// The AppleScript that selects `place`'s tab or terminal and brings its
    /// app forward, answering "found" or "missing"; nil when its terminal
    /// can't be told (no iTerm2 ID, or a terminal without a script here).
    static func script(for place: TerminalPlace) -> String? {
        switch place.terminal.app {
        case .iTerm2: place.terminal.iTermSessionId.map(iTerm(uniqueId:))
        case .ghostty: ghostty(folder: place.folder)
        default: nil
        }
    }

    /// The bundle ID of a terminal app ClaudeBar brings forward.
    static func bundleId(of app: SessionTerminal.App) -> String {
        switch app {
        case .iTerm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .terminal: "com.apple.Terminal"
        case .warp: "dev.warp.Warp-Stable"
        case .wezTerm: "com.github.wez.wezterm"
        }
    }

    // MARK: - AppleScript

    /// Selects the tab and window holding the session, then activates iTerm2.
    /// The ID is only letters, digits and hyphens (`SessionTerminal`), so it
    /// is safe inside the script's string.
    static func iTerm(uniqueId: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession is "\(uniqueId)" then
                            select aTab
                            tell aWindow to select
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
        """
    }

    /// Focuses the Ghostty terminal open in `folder`, comparing both paths
    /// with symlinks resolved, then activates Ghostty. The folder is escaped
    /// for the script's string.
    static func ghostty(folder: String) -> String {
        let escaped = folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "com.mitchellh.ghostty"
            set targetDir to "\(escaped)"
            try
                set targetDir to POSIX path of ((POSIX file targetDir) as alias)
            end try
            repeat with aWindow in windows
                repeat with t in every terminal of aWindow
                    set tDir to working directory of t
                    try
                        set tDir to POSIX path of ((POSIX file tDir) as alias)
                    end try
                    if tDir is targetDir then
                        focus t
                        set index of aWindow to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
        """
    }

    // MARK: - tmux

    /// The `tmux` commands that select a pane: its window, then the pane,
    /// zooming out first when another pane of the window is zoomed. Each is
    /// the arguments after `tmux`, aimed at the pane's own server.
    struct Tmux: Equatable {
        private let pane: String
        private let server: [String]

        init(_ tmux: SessionTerminal.TmuxPane) {
            pane = tmux.pane
            server = tmux.socket.map { ["-S", $0] } ?? []
        }

        var selectWindow: [String] { server + ["select-window", "-t", pane] }
        /// Answers the window's zoom flag, then whether the pane is the active one.
        var askZoom: [String] { server + ["display-message", "-p", "-t", pane, "#{window_zoomed_flag}#{pane_active}"] }
        var zoomOut: [String] { server + ["resize-pane", "-Z", "-t", pane] }
        var selectPane: [String] { server + ["select-pane", "-t", pane] }

        /// Whether `askZoom`'s answer says another pane is zoomed: the window
        /// is ("1"), and the pane isn't the active one ("0").
        static func anotherPaneZoomed(_ answer: String?) -> Bool {
            answer == "10"
        }
    }
}
