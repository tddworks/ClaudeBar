import Foundation
import Testing
@testable import Infrastructure

@Suite
struct ShellTests {

    // MARK: - Detection Tests

    @Test
    func `detects nushell from path`() {
        #expect(Shell.detect(from: "/opt/homebrew/bin/nu") == .nushell)
        #expect(Shell.detect(from: "/usr/local/bin/nushell") == .nushell)
        #expect(Shell.detect(from: "/home/user/.nix-profile/bin/nu") == .nushell)
    }

    @Test
    func `detects nushell case insensitively`() {
        #expect(Shell.detect(from: "/bin/Nu") == .nushell)
        #expect(Shell.detect(from: "/bin/NUSHELL") == .nushell)
    }

    @Test
    func `detects fish from path`() {
        #expect(Shell.detect(from: "/opt/homebrew/bin/fish") == .fish)
        #expect(Shell.detect(from: "/usr/local/bin/fish") == .fish)
        #expect(Shell.detect(from: "/usr/bin/fish") == .fish)
    }

    @Test
    func `detects posix shells`() {
        #expect(Shell.detect(from: "/bin/zsh") == .posix)
        #expect(Shell.detect(from: "/bin/bash") == .posix)
        #expect(Shell.detect(from: "/bin/sh") == .posix)
        #expect(Shell.detect(from: "/usr/local/bin/zsh") == .posix)
        #expect(Shell.detect(from: "/opt/homebrew/bin/bash") == .posix)
    }

    @Test
    func `defaults to posix for unknown shells`() {
        #expect(Shell.detect(from: "/some/unknown/shell") == .posix)
        #expect(Shell.detect(from: "/bin/ksh") == .posix)
        #expect(Shell.detect(from: "/bin/dash") == .posix)
    }

    // MARK: - Command Generation Tests

    @Test
    func `posix which command format`() {
        let args = Shell.posix.whichArguments(for: "claude")
        #expect(args == ["-l", "-c", "which claude"])
    }

    @Test
    func `fish which command format`() {
        let args = Shell.fish.whichArguments(for: "codex")
        #expect(args == ["-l", "-c", "which codex"])
    }

    @Test
    func `nushell which command uses external which`() {
        let args = Shell.nushell.whichArguments(for: "claude")
        #expect(args == ["-l", "-c", "^which claude"])
    }

    @Test
    func `which command allows dots and hyphens in tool names`() {
        let args = Shell.posix.whichArguments(for: "my-tool.sh")
        #expect(args == ["-l", "-c", "which my-tool.sh"])
    }

    @Test
    func `which command rejects shell metacharacters`() {
        // Semicolon injection attempt
        let args1 = Shell.posix.whichArguments(for: "claude; rm -rf /")
        #expect(args1 == ["-l", "-c", "which ''"])

        // Command substitution attempt
        let args2 = Shell.posix.whichArguments(for: "$(whoami)")
        #expect(args2 == ["-l", "-c", "which ''"])

        // Backtick injection attempt
        let args3 = Shell.posix.whichArguments(for: "`id`")
        #expect(args3 == ["-l", "-c", "which ''"])

        // Quote injection attempt
        let args4 = Shell.posix.whichArguments(for: "tool'injection")
        #expect(args4 == ["-l", "-c", "which ''"])

        // Space injection attempt
        let args5 = Shell.posix.whichArguments(for: "tool with spaces")
        #expect(args5 == ["-l", "-c", "which ''"])

        // Nushell also rejects metacharacters
        let args6 = Shell.nushell.whichArguments(for: "claude; rm -rf /")
        #expect(args6 == ["-l", "-c", "which ''"])
    }

    @Test
    func `posix path command format`() {
        let args = Shell.posix.pathArguments()
        #expect(args == ["-l", "-c", "echo $PATH"])
    }

    @Test
    func `fish path command format`() {
        let args = Shell.fish.pathArguments()
        #expect(args == ["-l", "-c", "echo $PATH"])
    }

    @Test
    func `nushell path command joins with colon`() {
        let args = Shell.nushell.pathArguments()
        #expect(args == ["-l", "-c", "$env.PATH | str join ':'"])
    }

    // MARK: - Output Parsing Tests

    @Test
    func `posix parses simple path output`() {
        let output = "/usr/local/bin/claude\n"
        #expect(Shell.posix.parseWhichOutput(output) == "/usr/local/bin/claude")
    }

    @Test
    func `posix parses path with spaces`() {
        let output = "  /usr/local/bin/claude  \n"
        #expect(Shell.posix.parseWhichOutput(output) == "/usr/local/bin/claude")
    }

    @Test
    func `posix returns nil for empty output`() {
        #expect(Shell.posix.parseWhichOutput("") == nil)
        #expect(Shell.posix.parseWhichOutput("   \n") == nil)
    }

    @Test
    func `fish parses simple path output`() {
        let output = "/opt/homebrew/bin/gemini\n"
        #expect(Shell.fish.parseWhichOutput(output) == "/opt/homebrew/bin/gemini")
    }

    @Test
    func `nushell parses clean path output`() {
        let output = "/Users/user/.local/bin/claude\n"
        #expect(Shell.nushell.parseWhichOutput(output) == "/Users/user/.local/bin/claude")
    }

    @Test
    func `nushell rejects table output as safety fallback`() {
        let tableOutput = """
        ╭───┬─────────┬─────────────────────────────────────────────────────┬──────────╮
        │ # │ command │                        path                         │   type   │
        ├───┼─────────┼─────────────────────────────────────────────────────┼──────────┤
        │ 0 │ claude  │ /Users/user/.local/bin/claude                       │ external │
        ╰───┴─────────┴─────────────────────────────────────────────────────┴──────────╯
        """
        #expect(Shell.nushell.parseWhichOutput(tableOutput) == nil)
    }

    @Test
    func `nushell rejects partial table output`() {
        #expect(Shell.nushell.parseWhichOutput("│ some output") == nil)
        #expect(Shell.nushell.parseWhichOutput("╭───") == nil)
        #expect(Shell.nushell.parseWhichOutput("╰───╯") == nil)
    }

    @Test
    func `nushell rejects all table box-drawing characters`() {
        #expect(Shell.nushell.parseWhichOutput("╮───") == nil)
        #expect(Shell.nushell.parseWhichOutput("╯───") == nil)
        #expect(Shell.nushell.parseWhichOutput("path─with─box") == nil)
        #expect(Shell.nushell.parseWhichOutput("├──┼──┤") == nil)
    }

    @Test
    func `path output parsing trims whitespace`() {
        let output = "  /usr/bin:/bin:/usr/local/bin  \n"
        #expect(Shell.posix.parsePathOutput(output) == "/usr/bin:/bin:/usr/local/bin")
        #expect(Shell.nushell.parsePathOutput(output) == "/usr/bin:/bin:/usr/local/bin")
    }

    // MARK: - Shell.current Tests

    @Test
    func `current returns shell based on SHELL environment variable`() {
        // Shell.current reads from ProcessInfo which we can't easily mock,
        // but we can verify it returns a valid shell type and matches detect()
        let current = Shell.current
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let expected = Shell.detect(from: shellPath)
        #expect(current == expected)
    }
}
