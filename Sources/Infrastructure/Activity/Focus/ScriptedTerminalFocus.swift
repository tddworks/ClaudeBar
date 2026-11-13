import AppKit
import Foundation
import Domain

/// Brings a Claude Code session's terminal forward: selects its tmux pane,
/// then its iTerm2 tab or Ghostty terminal by AppleScript, else brings the app
/// to the front (docs/features/activity/session-hooks/design.md, *Bring a
/// session forward*). What it runs is `TerminalScripts`'; this only runs it.
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
            selectTmuxPane(TerminalScripts.Tmux(tmux))
        }
        guard let source = TerminalScripts.script(for: place) else { return false }
        return run(source) == "found"
    }

    @MainActor
    private static func activate(_ app: SessionTerminal.App) {
        let bundleId = TerminalScripts.bundleId(of: app)
        guard let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            AppLog.ui.info("The terminal of a Claude Code session isn't running; nothing to bring forward")
            return
        }
        match.activate()
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

    /// How long one `tmux` command may take before it is stopped.
    private static let tmuxDeadline: TimeInterval = 5

    private static let tmuxPath: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func selectTmuxPane(_ tmux: TerminalScripts.Tmux) {
        guard let tmuxPath else {
            AppLog.ui.info("tmux isn't installed where ClaudeBar looks; bringing the terminal forward without its pane")
            return
        }
        runTmux(tmuxPath, tmux.selectWindow)
        if TerminalScripts.Tmux.anotherPaneZoomed(runTmux(tmuxPath, tmux.askZoom)) {
            runTmux(tmuxPath, tmux.zoomOut)
        }
        runTmux(tmuxPath, tmux.selectPane)
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
        // A tmux client stuck on a server that doesn't answer would hold the
        // queue, and every later click with it; stop it after a while.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + tmuxDeadline, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
