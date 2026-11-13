import Testing
@testable import Domain

@Suite
struct SessionTerminalTests {
    private let iTermID = "w0t1p0:4F1C2B3A-1234-4ABC-9DEF-0123456789AB"

    @Test func `should run in iTerm2 when iTerm2 says so`() {
        let terminal = SessionTerminal(environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": iTermID])

        #expect(terminal?.app == .iTerm2)
        #expect(terminal?.iTermSessionId == "4F1C2B3A-1234-4ABC-9DEF-0123456789AB")
    }

    @Test func `should run in iTerm2 inside tmux`() {
        let terminal = SessionTerminal(environment: [
            "TERM_PROGRAM": "tmux",
            "LC_TERMINAL": "iTerm2",
            "ITERM_SESSION_ID": iTermID,
            "TMUX": "/private/tmp/tmux-501/default,4242,0",
            "TMUX_PANE": "%3",
        ])

        #expect(terminal?.app == .iTerm2)
        #expect(terminal?.tmux == SessionTerminal.TmuxPane(pane: "%3", socket: "/private/tmp/tmux-501/default"))
    }

    @Test func `should keep a tmux server whose path has a comma`() {
        let terminal = SessionTerminal(environment: ["TMUX": "/tmp/a,b/default,4242,0", "TMUX_PANE": "%1"])

        #expect(terminal?.tmux?.socket == "/tmp/a,b/default")
    }

    @Test func `should keep only the iTerm2 session's own ID`() {
        let terminal = SessionTerminal(environment: ["LC_TERMINAL": "iTerm2", "ITERM_SESSION_ID": "4F1C2B3A-1234"])

        #expect(terminal?.iTermSessionId == "4F1C2B3A-1234")
    }

    @Test func `should have no iTerm2 session when its ID isn't one`() {
        let terminal = SessionTerminal(environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:\" & do shell script \"x"])

        #expect(terminal?.app == .iTerm2)
        #expect(terminal?.iTermSessionId == nil)
    }

    @Test func `should run in Ghostty`() {
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "ghostty"])?.app == .ghostty)
    }

    @Test func `should run in Terminal, Warp or WezTerm`() {
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "Apple_Terminal"])?.app == .terminal)
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "WarpTerminal"])?.app == .warp)
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "WezTerm"])?.app == .wezTerm)
    }

    @Test func `should name no app for a terminal it can't bring forward`() {
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "vscode"]) == nil)
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "Hyper"]) == nil)
    }

    @Test func `should run nowhere known when nothing was said`() {
        #expect(SessionTerminal(environment: [:]) == nil)
        #expect(SessionTerminal(environment: ["TERM_PROGRAM": "", "TMUX_PANE": " "]) == nil)
    }

    @Test func `should name no app inside tmux when the terminal outside isn't known`() {
        let terminal = SessionTerminal(environment: ["TERM_PROGRAM": "tmux", "TMUX_PANE": "%2"])

        #expect(terminal?.app == nil)
        #expect(terminal?.tmux?.pane == "%2")
    }
}
