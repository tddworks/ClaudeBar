import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// What runs to bring a Claude Code session's terminal forward.
@Suite
struct TerminalScriptsTests {
    private func place(_ terminal: SessionTerminal, folder: String = "/code/tinyshop") -> TerminalPlace {
        TerminalPlace(terminal: terminal, folder: folder)
    }

    // MARK: - Which script

    @Test
    func `should pick the iTerm2 session by its ID`() throws {
        let script = try #require(TerminalScripts.script(for: place(SessionTerminal(app: .iTerm2, iTermSessionId: "ABC-123"))))

        #expect(script.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(script.contains(#"if unique ID of aSession is "ABC-123" then"#))
    }

    @Test
    func `should find the Ghostty terminal by the session's folder`() throws {
        let script = try #require(TerminalScripts.script(for: place(SessionTerminal(app: .ghostty))))

        #expect(script.contains(#"tell application id "com.mitchellh.ghostty""#))
        #expect(script.contains(#"set targetDir to "/code/tinyshop""#))
    }

    @Test
    func `should have no script for an iTerm2 session without an ID`() {
        #expect(TerminalScripts.script(for: place(SessionTerminal(app: .iTerm2))) == nil)
    }

    @Test
    func `should have no script for a terminal that can only be brought forward`() {
        for app: SessionTerminal.App in [.terminal, .warp, .wezTerm, .other("kitty")] {
            #expect(TerminalScripts.script(for: place(SessionTerminal(app: app))) == nil)
        }
    }

    @Test
    func `should keep a folder with quotes and backslashes inside the Ghostty script's string`() throws {
        let script = try #require(TerminalScripts.script(for: place(SessionTerminal(app: .ghostty), folder: #"/code/a"b\c"#)))

        #expect(script.contains(#"set targetDir to "/code/a\"b\\c""#))
    }

    // MARK: - Which app

    @Test
    func `should know each terminal app by its bundle ID`() {
        #expect(TerminalScripts.bundleId(of: .iTerm2) == "com.googlecode.iterm2")
        #expect(TerminalScripts.bundleId(of: .ghostty) == "com.mitchellh.ghostty")
        #expect(TerminalScripts.bundleId(of: .terminal) == "com.apple.Terminal")
        #expect(TerminalScripts.bundleId(of: .warp) == "dev.warp.Warp-Stable")
        #expect(TerminalScripts.bundleId(of: .wezTerm) == "com.github.wez.wezterm")
        #expect(TerminalScripts.bundleId(of: .other("kitty")) == nil)
    }

    // MARK: - tmux

    @Test
    func `should select the pane's window and then the pane on its own server`() {
        let tmux = TerminalScripts.Tmux(SessionTerminal.TmuxPane(pane: "%3", socket: "/tmp/tmux-501/default"))

        #expect(tmux.selectWindow == ["-S", "/tmp/tmux-501/default", "select-window", "-t", "%3"])
        #expect(tmux.selectPane == ["-S", "/tmp/tmux-501/default", "select-pane", "-t", "%3"])
        #expect(tmux.askZoom == ["-S", "/tmp/tmux-501/default", "display-message", "-p", "-t", "%3", "#{window_zoomed_flag}#{pane_active}"])
        #expect(tmux.zoomOut == ["-S", "/tmp/tmux-501/default", "resize-pane", "-Z", "-t", "%3"])
    }

    @Test
    func `should use the default tmux server when the socket is unknown`() {
        let tmux = TerminalScripts.Tmux(SessionTerminal.TmuxPane(pane: "%3", socket: nil))

        #expect(tmux.selectPane == ["select-pane", "-t", "%3"])
    }

    @Test
    func `should zoom out only when another pane of the window is zoomed`() {
        #expect(TerminalScripts.Tmux.anotherPaneZoomed("10"))
        #expect(!TerminalScripts.Tmux.anotherPaneZoomed("11"))
        #expect(!TerminalScripts.Tmux.anotherPaneZoomed("00"))
        #expect(!TerminalScripts.Tmux.anotherPaneZoomed(nil))
    }
}
