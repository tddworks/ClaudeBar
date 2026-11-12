import AppKit
import Foundation
import Domain

/// Brings a Claude Code session's terminal forward: selects its tmux pane,
/// then its iTerm2 tab or Ghostty terminal by AppleScript, else brings the app
/// to the front (docs/features/activity/session-hooks/design.md, *Bring a
/// session forward*).
///
/// Sandboxed (the App Store build) it can neither run `tmux` nor script
/// another app, so it only brings the app to the front.
public struct ScriptedTerminalFocus: TerminalFocus {
    private let isSandboxed: Bool

    public init(isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil) {
        self.isSandboxed = isSandboxed
    }

    public func bringForward(_ place: TerminalPlace) async {
        let isSandboxed = isSandboxed
        let broughtForward: Bool = await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.script(place, isSandboxed: isSandboxed))
            }
        }
        guard !broughtForward, let app = place.terminal.app else { return }
        await MainActor.run { Self.activate(app) }
    }

    /// AppleScript and `tmux` block; they run one at a time, off the main thread.
    private static let queue = DispatchQueue(label: "ClaudeBar.TerminalFocus")

    /// Selects the pane, then the tab or terminal; true when a script found
    /// it and brought the app forward itself.
    private static func script(_ place: TerminalPlace, isSandboxed: Bool) -> Bool {
        guard !isSandboxed else { return false }
        if let tmux = place.terminal.tmux {
            selectTmuxPane(tmux)
        }
        switch place.terminal.app {
        case .iTerm2:
            guard let id = place.terminal.iTermSessionId else { return false }
            return run(iTermScript(uniqueId: id)) == "found"
        case .ghostty:
            return run(ghosttyScript(folder: place.folder)) == "found"
        default:
            return false
        }
    }

    // MARK: - Apps

    private static let bundleIds: [SessionTerminal.App: String] = [
        .iTerm2: "com.googlecode.iterm2",
        .ghostty: "com.mitchellh.ghostty",
        .terminal: "com.apple.Terminal",
        .warp: "dev.warp.Warp-Stable",
        .wezTerm: "com.github.wez.wezterm",
    ]

    @MainActor
    private static func activate(_ app: SessionTerminal.App) {
        let running = NSWorkspace.shared.runningApplications
        let match: NSRunningApplication? = if let bundleId = bundleIds[app] {
            running.first { $0.bundleIdentifier == bundleId }
        } else if case .other(let name) = app {
            running.first { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }
        } else {
            nil
        }
        guard let match else {
            AppLog.ui.info("The terminal of a Claude Code session isn't running; nothing to bring forward")
            return
        }
        match.activate()
    }

    // MARK: - AppleScript

    /// Selects the tab and window holding the session, then activates iTerm2.
    /// The ID is only letters, digits and hyphens (`SessionTerminal`), so it
    /// is safe inside the script's string.
    private static func iTermScript(uniqueId: String) -> String {
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
    /// with symlinks resolved, then activates Ghostty.
    private static func ghosttyScript(folder: String) -> String {
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

    /// Runs `source`, answering its result; nil when it failed (macOS refused
    /// the permission to control the app, say).
    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            AppLog.ui.warning("Couldn't bring a Claude Code session's terminal forward: AppleScript error \(error[NSAppleScript.errorNumber] ?? "?")")
            return nil
        }
        return result.stringValue
    }

    // MARK: - tmux

    private static let tmuxPath: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Selects the pane's window, zooms out when another pane of it is
    /// zoomed, then selects the pane.
    private static func selectTmuxPane(_ tmux: SessionTerminal.TmuxPane) {
        guard let tmuxPath else {
            AppLog.ui.info("tmux isn't installed where ClaudeBar looks; bringing the terminal forward without its pane")
            return
        }
        let server = tmux.socket.map { ["-S", $0] } ?? []
        runTmux(tmuxPath, server + ["select-window", "-t", tmux.pane])
        // "1" zoomed, then "0": the pane isn't the one zoomed.
        if runTmux(tmuxPath, server + ["display-message", "-p", "-t", tmux.pane, "#{window_zoomed_flag}#{pane_active}"]) == "10" {
            runTmux(tmuxPath, server + ["resize-pane", "-Z", "-t", tmux.pane])
        }
        runTmux(tmuxPath, server + ["select-pane", "-t", tmux.pane])
    }

    @discardableResult
    private static func runTmux(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
